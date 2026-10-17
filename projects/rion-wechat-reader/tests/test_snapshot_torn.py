"""Snapshot 撕裂重拍：微信并发写入时逐文件复制会产生 db 页与 -wal 记录分属两时刻的
副本，只读打开报 unable to open database file。判据是 db/-wal 的 (size, mtime) 指纹，
撕裂必须清场重拍（有限次）；一致时只拍一次。"""

import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import rion_wechat_reader as reader


class TornSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.db = self.root / "message_2.db"
        self.db.write_bytes(b"sqlite-page-1")
        self.wal = Path(str(self.db) + "-wal")
        self.wal.write_bytes(b"wal-bytes")
        self.shm = Path(str(self.db) + "-shm")
        self.shm.write_bytes(b"shm-bytes")

    def tearDown(self):
        self.temp.cleanup()

    def test_consistent_sources_take_snapshot_once(self):
        calls: list[int] = []

        def collect(snapshot_self, target_dir):
            calls.append(1)
            shutil.copy2(self.db, Path(target_dir) / self.db.name)
            shutil.copy2(self.wal, Path(target_dir) / self.wal.name)
            shutil.copy2(self.shm, Path(target_dir) / self.shm.name)
            return Path(target_dir) / snapshot_self.source.name

        with mock.patch.object(reader.Snapshot, "_collect", autospec=True, side_effect=collect):
            with reader.Snapshot(self.db) as snap:
                self.assertTrue(snap.exists())
        self.assertEqual(len(calls), 1)

    def test_torn_first_copy_is_recaptured(self):
        calls: list[int] = []

        def collect(snapshot_self, target_dir):
            calls.append(1)
            target_dir = Path(target_dir)
            shutil.copy2(self.db, target_dir / self.db.name)
            if len(calls) == 1:
                # 首拍撕裂：-wal 落地后源被微信继续写入 → 快照 -wal 指纹落后
                (target_dir / self.wal.name).write_bytes(b"partial")
                os.utime(target_dir / self.wal.name, (0, 0))
            else:
                shutil.copy2(self.wal, target_dir / self.wal.name)
            shutil.copy2(self.shm, target_dir / self.shm.name)
            return target_dir / snapshot_self.source.name

        with mock.patch.object(reader.Snapshot, "_collect", autospec=True, side_effect=collect):
            with mock.patch.object(reader.time, "sleep"):
                with reader.Snapshot(self.db) as snap:
                    self.assertTrue(snap.exists())
        self.assertEqual(len(calls), 2, "撕裂后应整组重拍一次")

    def test_endlessly_torn_falls_back_after_limited_recaptures(self):
        calls: list[int] = []

        def collect(snapshot_self, target_dir):
            calls.append(1)
            target_dir = Path(target_dir)
            shutil.copy2(self.db, target_dir / self.db.name)
            (target_dir / self.wal.name).write_bytes(b"stale")
            os.utime(target_dir / self.wal.name, (0, 0))
            return target_dir / snapshot_self.source.name

        with mock.patch.object(reader.Snapshot, "_collect", autospec=True, side_effect=collect):
            with mock.patch.object(reader.time, "sleep"):
                with reader.Snapshot(self.db) as snap:
                    # 永远不一致：用尽重拍后仍返回末次副本，打开失败由调用方按既有契约处理
                    self.assertTrue(snap.exists())
        self.assertEqual(len(calls), 4)

    def test_absent_wal_is_consistent(self):
        self.wal.unlink()
        self.shm.unlink()
        calls: list[int] = []

        def collect(snapshot_self, target_dir):
            calls.append(1)
            shutil.copy2(self.db, Path(target_dir) / self.db.name)
            return Path(target_dir) / snapshot_self.source.name

        with mock.patch.object(reader.Snapshot, "_collect", autospec=True, side_effect=collect):
            with reader.Snapshot(self.db):
                pass
        self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
