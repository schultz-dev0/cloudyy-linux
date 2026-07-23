import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from lib.ccd import model, online_wallpapers, protocol


def wait_for(condition, timeout=5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return True
        time.sleep(0.02)
    return False


class FakeResponse:
    def __init__(self, *, json_data=None, content=b"", status=200):
        self._json = json_data
        self.content = content
        self.status_code = status

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")

    def json(self):
        return self._json


SEARCH_RESPONSE = {
    "data": [
        {
            "id": "abc123",
            "path": "https://example.com/full/abc123.jpg",
            "url": "https://wallhaven.cc/w/abc123",
            "resolution": "3840x2160",
            "thumbs": {"small": "https://example.com/thumb/abc123.jpg"},
        },
    ],
    "meta": {"current_page": 1, "last_page": 3},
}


class OnlineWallpapersTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        thumb_patch = mock.patch.object(
            online_wallpapers, "THUMB_DIR", Path(self.tmp.name) / "thumbs"
        )
        thumb_patch.start()
        self.addCleanup(thumb_patch.stop)

        self.events = []
        events_patch = mock.patch.object(
            protocol, "write_line", lambda payload: self.events.append(payload)
        )
        events_patch.start()
        self.addCleanup(events_patch.stop)

        mode_patch = mock.patch.object(model, "theme_mode", lambda: "dark")
        mode_patch.start()
        self.addCleanup(mode_patch.stop)

    def toast_events(self):
        return [e for e in self.events if e.get("event") == "toast"]

    def action_done_events(self):
        return [e for e in self.events if e.get("event") == "action_done"]


class TestSearch(OnlineWallpapersTest):
    def test_query_uses_relevance_sorting(self):
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.side_effect = [
                FakeResponse(json_data=SEARCH_RESPONSE),
                FakeResponse(content=b"thumbbytes"),
            ]
            result = online_wallpapers.search({"query": "mountains", "page": 1})

        search_call = get.call_args_list[0]
        self.assertEqual(search_call.kwargs["params"]["q"], "mountains")
        self.assertEqual(search_call.kwargs["params"]["sorting"], "relevance")
        self.assertEqual(len(result["results"]), 1)
        self.assertEqual(result["results"][0]["id"], "abc123")
        self.assertEqual(result["results"][0]["full_url"], SEARCH_RESPONSE["data"][0]["path"])
        self.assertEqual(result["results"][0]["page_url"], SEARCH_RESPONSE["data"][0]["url"])
        self.assertTrue(result["has_more"])  # current_page 1 < last_page 3

    def test_no_query_defaults_to_hot_sorting(self):
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.side_effect = [
                FakeResponse(json_data=SEARCH_RESPONSE),
                FakeResponse(content=b"thumbbytes"),
            ]
            online_wallpapers.search({})

        self.assertEqual(get.call_args_list[0].kwargs["params"]["sorting"], "hot")

    def test_min_res_maps_to_atleast_filter(self):
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.side_effect = [
                FakeResponse(json_data=SEARCH_RESPONSE),
                FakeResponse(content=b"thumbbytes"),
            ]
            online_wallpapers.search({"min_res": "2560x1440"})

        self.assertEqual(get.call_args_list[0].kwargs["params"]["atleast"], "2560x1440")

    def test_no_min_res_omits_atleast_filter(self):
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.side_effect = [
                FakeResponse(json_data=SEARCH_RESPONSE),
                FakeResponse(content=b"thumbbytes"),
            ]
            online_wallpapers.search({})

        self.assertNotIn("atleast", get.call_args_list[0].kwargs["params"])

    def test_toplist_sort_adds_top_range(self):
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.side_effect = [
                FakeResponse(json_data=SEARCH_RESPONSE),
                FakeResponse(content=b"thumbbytes"),
            ]
            online_wallpapers.search({"sort": "toplist"})

        params = get.call_args_list[0].kwargs["params"]
        self.assertEqual(params["sorting"], "toplist")
        self.assertEqual(params["topRange"], "1M")

    def test_thumbnail_cached_to_disk_and_reused(self):
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.side_effect = [
                FakeResponse(json_data=SEARCH_RESPONSE),
                FakeResponse(content=b"thumbbytes"),
            ]
            result = online_wallpapers.search({"page": 1})

        thumb_path = Path(result["results"][0]["thumb"])
        self.assertTrue(thumb_path.exists())
        self.assertEqual(thumb_path.read_bytes(), b"thumbbytes")

        # Second search hitting the same wallhaven id must not re-fetch the thumb.
        with mock.patch.object(online_wallpapers.requests, "get") as get2:
            get2.side_effect = [FakeResponse(json_data=SEARCH_RESPONSE)]
            online_wallpapers.search({"page": 1})
        self.assertEqual(get2.call_count, 1)  # only the search call, no thumb fetch

    def test_api_failure_returns_empty_results_not_a_crash(self):
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.side_effect = RuntimeError("network down")
            result = online_wallpapers.search({"query": "x"})

        self.assertEqual(result["results"], [])
        self.assertFalse(result["has_more"])
        self.assertIn("error", result)

    def test_last_page_reports_no_more(self):
        response = {
            "data": [],
            "meta": {"current_page": 3, "last_page": 3},
        }
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.return_value = FakeResponse(json_data=response)
            result = online_wallpapers.search({"page": 3})
        self.assertFalse(result["has_more"])


class TestApplyOrDownload(OnlineWallpapersTest):
    def test_requires_url_and_directory(self):
        with self.assertRaises(ValueError):
            online_wallpapers.apply_or_download({"url": "", "dark_directory": ""})

    def test_download_only_saves_and_toasts_no_apply_command_run(self):
        dest_dir = Path(self.tmp.name) / "walls"
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.return_value = FakeResponse(content=b"imagebytes")
            with mock.patch.object(online_wallpapers.actions, "run_command") as run_cmd:
                online_wallpapers.apply_or_download({
                    "url": "https://example.com/full/x.jpg",
                    "dark_directory": str(dest_dir),
                    "apply": False,
                })
                self.assertTrue(wait_for(lambda: self.toast_events()))
        run_cmd.assert_not_called()
        saved = list(dest_dir.glob("*.jpg"))
        self.assertEqual(len(saved), 1)
        self.assertEqual(saved[0].read_bytes(), b"imagebytes")
        self.assertEqual(saved[0].name, "0000.jpg")

    def test_apply_runs_apply_command_with_downloaded_path(self):
        dest_dir = Path(self.tmp.name) / "walls"
        out = Path(self.tmp.name) / "applied.txt"
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.return_value = FakeResponse(content=b"imagebytes")
            online_wallpapers.apply_or_download({
                "url": "https://example.com/full/x.jpg",
                "dark_directory": str(dest_dir),
                "apply_command": f"bash -c 'echo {{path}} > {out}'",
                "apply": True,
            })
            self.assertTrue(wait_for(lambda: self.action_done_events()))
        self.assertTrue(out.exists())
        saved = next(dest_dir.glob("*.jpg"))
        self.assertIn(str(saved), out.read_text())

    def test_apply_command_gets_explicit_mode_substituted(self):
        # setUp mocks theme_mode() to "dark"; applying with mode="light" should
        # substitute "light" into {mode}, not the current system theme — so
        # applying a wallpaper you picked for the Light pool also switches
        # system theme mode to match, instead of applying it silently under
        # whatever mode happened to already be active.
        dest_dir = Path(self.tmp.name) / "walls"
        out = Path(self.tmp.name) / "applied.txt"
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.return_value = FakeResponse(content=b"imagebytes")
            online_wallpapers.apply_or_download({
                "url": "https://example.com/full/x.jpg",
                "light_directory": str(dest_dir),
                "apply_command": f"bash -c 'echo {{mode}} > {out}'",
                "apply": True,
                "mode": "light",
            })
            self.assertTrue(wait_for(lambda: self.action_done_events()))
        self.assertEqual(out.read_text().strip(), "light")

    def test_sequential_filenames_dont_collide(self):
        dest_dir = Path(self.tmp.name) / "walls"
        dest_dir.mkdir(parents=True)
        (dest_dir / "0000.jpg").write_bytes(b"existing")
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.return_value = FakeResponse(content=b"new")
            online_wallpapers.apply_or_download({
                "url": "https://example.com/full/y.jpg",
                "dark_directory": str(dest_dir),
                "apply": False,
            })
            self.assertTrue(wait_for(lambda: self.toast_events()))
        self.assertTrue((dest_dir / "0001.jpg").exists())

    def test_explicit_mode_overrides_system_theme(self):
        # setUp mocks theme_mode() to "dark" — passing mode="light" should
        # still land in light_directory, not dark_directory.
        light_dir = Path(self.tmp.name) / "light"
        dark_dir = Path(self.tmp.name) / "dark"
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.return_value = FakeResponse(content=b"new")
            online_wallpapers.apply_or_download({
                "url": "https://example.com/full/z.jpg",
                "light_directory": str(light_dir),
                "dark_directory": str(dark_dir),
                "apply": False,
                "mode": "light",
            })
            self.assertTrue(wait_for(lambda: self.toast_events()))
        self.assertEqual(len(list(light_dir.glob("*.jpg"))), 1)
        self.assertFalse(dark_dir.exists())

    def test_invalid_mode_falls_back_to_system_theme(self):
        dark_dir = Path(self.tmp.name) / "dark"
        with mock.patch.object(online_wallpapers.requests, "get") as get:
            get.return_value = FakeResponse(content=b"new")
            online_wallpapers.apply_or_download({
                "url": "https://example.com/full/z.jpg",
                "dark_directory": str(dark_dir),
                "apply": False,
                "mode": "sideways",
            })
            self.assertTrue(wait_for(lambda: self.toast_events()))
        self.assertEqual(len(list(dark_dir.glob("*.jpg"))), 1)


class TestGetThemeMode(OnlineWallpapersTest):
    def test_reports_current_theme_mode(self):
        self.assertEqual(online_wallpapers.get_theme_mode({}), {"mode": "dark"})


if __name__ == "__main__":
    unittest.main()
