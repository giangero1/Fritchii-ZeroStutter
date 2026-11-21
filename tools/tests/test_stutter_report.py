# SPDX-License-Identifier: GPL-3.0-or-later
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("stutter_report", Path(__file__).resolve().parents[1] / "stutter_report.py")
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)


class StutterReportTests(unittest.TestCase):
    def test_aggregates_do_not_become_frame_counts_or_double_count_build_work(self):
        lines = [
            "[ 0.0] Lichii Version: private C:/secret/name | hybrid/zelda-audit-55bf2d795a",
            "[ 1.0] Booting game: 0400486024DEC000",
            "[ 8.0] Total Pipeline Count: 1496",
            "[ 20.0] Runtime pipelines in the last 10 s: 66 built, 662.5 ms on the GPU thread (96.4 ms of it graphics SPIR-V), 0.0 ms graphics SPIR-V on workers, 7.2 ms of draws held for unbuilt pipelines",
            "[ 21.0] Graphics pipeline built on the GPU thread in 39.4 ms: private shader data",
            "[ 22.0] Host pacing on: 403 frames at 239.964 Hz; shown for 1/2/3/4/5+ refreshes: 0/0/0/168/235 (same refresh 0); interval mean 24.82 ms, max 1443.08; held 53",
            "[ 23.0] HW.Memory <Error> private_path: Unmapped Device ReadBlock @ private_address",
        ]
        result = REPORT.analyze(lines)["sessions"][0]
        self.assertEqual(result["build_sha"], "55bf2d795a")
        self.assertEqual(result["pipeline_summary"]["gpu_thread_ms"], 662.5)
        self.assertEqual(result["logged_runtime_builds"]["graphics"]["sum_ms"], 39.4)
        self.assertEqual(result["pacer"]["max_window_interval_ms"], 1443.08)
        self.assertIsNone(result["pacer"]["frames_over_500ms"])
        self.assertEqual(result["pacer"]["windows_with_max_over_500ms"], 1)
        self.assertEqual(result["error_counts"], {"unmapped_device_read": 1})
        self.assertNotIn("private", json.dumps(result))

    def test_rate_limited_renderer_and_gpu_samples_remain_samples(self):
        result = REPORT.analyze([
            "[ 3.0] DKB renderer renderer_frame=20 cpu_frame_wall_ms=-1.000 cpu_composite_wall_ms=10.0",
            "[ 4.0] DKB renderer renderer_frame=80 cpu_frame_wall_ms=600.000 cpu_composite_wall_ms=10.0",
            "[ 4.1] DKB gpu_frame renderer_frame=80 last_submission_tick=200 gpu_frame_span_ms=700.000 gpu_submission_sum_ms=20.0",
            "[ 4.2] DKB gpu_frame renderer_frame=81 gpu_frame_span_ms=-1.000",
        ])["sessions"][0]["sampled_frame_records"]
        self.assertEqual(result["renderer_cpu_intervals"]["records"], 1)
        self.assertEqual(result["renderer_cpu_intervals"]["observed_over_500ms"], 1)
        self.assertEqual(result["gpu_frame_spans"]["max_ms"], 700)
        self.assertIsNone(result["complete_frame_count_over_500ms"])

    def test_multiple_sessions_and_time_filter_keep_metadata(self):
        result = REPORT.analyze([
            "[ 0.0] Lichii Version: nx2-abcdef1234",
            "[ 1.0] Booting game: 0400486024DEC000",
            "[ 2.0] Compute pipeline built on the GPU thread in 3.0 ms:",
            "[ 5.0] Compute pipeline built on the GPU thread in 4.0 ms:",
            "[ 7.0] Booting game: 0400C3F00006E000",
            "[ 8.0] GPU back thread per second: | pipeline 12.0 ms (2/s)",
        ], since=4, until=8)["sessions"]
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0]["logged_runtime_builds"]["compute"]["sum_ms"], 4)
        self.assertEqual(result[1]["build_sha"], "abcdef1234")
        self.assertEqual(result[1]["gpu_profile"]["records"], 1)

    def test_bounded_tail_ignores_fragments(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "local.log"
            path.write_bytes(b"private_prefix\n[ 1.0] complete\n[ 2.0] partial")
            lines, bounds = REPORT.read_bounded(path, 32, 2)
            self.assertEqual(lines, ["[ 1.0] complete"])
            self.assertTrue(bounds["prefix_truncated"])
            self.assertTrue(bounds["incomplete_final_line_ignored"])

    def test_out_of_date_is_not_reported_as_out_of_memory(self):
        errors = REPORT.analyze([
            "[ 1.0] Render.Vulkan <Error> VK_ERROR_OUT_OF_DATE_KHR",
            "[ 2.0] Render.Vulkan <Critical> VK_ERROR_OUT_OF_DEVICE_MEMORY",
            "[ 3.0] Render.Vulkan <Critical> VK_ERROR_DEVICE_LOST",
        ])["sessions"][0]["error_counts"]
        self.assertEqual(errors, {"other": 1, "allocation_or_memory": 1, "device_lost": 1})


if __name__ == "__main__":
    unittest.main()
