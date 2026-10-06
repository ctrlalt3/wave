"""Exercise the actual Flask like handlers without launching background services."""
import ast
import copy
from pathlib import Path
import threading
import unittest

from flask import Flask, jsonify, request


class LikeEndpointTests(unittest.TestCase):
    def setUp(self):
        self.stats = {}
        self.aliases = {}
        app = Flask(__name__)
        source = ast.parse((Path(__file__).resolve().parents[1] / 'app.py').read_text())
        handlers = [node for node in source.body if isinstance(node, ast.FunctionDef)
                    and node.name in {'get_likes', 'toggle_like'}]
        namespace = {'app': app, 'request': request, 'jsonify': jsonify,
                     '_stats_lock': threading.Lock(),
                     'resolve_cloud_track': lambda path: self.aliases.get(path, path),
                     '_load_stats': lambda: copy.deepcopy(self.stats),
                     '_save_stats': self.save_stats}
        exec(compile(ast.Module(body=handlers, type_ignores=[]), 'app.py', 'exec'), namespace)
        self.client = app.test_client()

    def save_stats(self, stats):
        self.stats = copy.deepcopy(stats)

    def like(self, **body):
        return self.client.post('/api/like', json={'track': 'House/song.mp3', **body})

    def test_repeated_save_sets_heart_and_is_visible_to_folder_read(self):
        self.assertTrue(self.like(liked=True).get_json()['liked'])
        self.assertTrue(self.like(liked=True).get_json()['liked'])
        self.assertEqual(self.client.get('/api/likes').get_json(), {'House/song.mp3': True})

    def test_explicit_unlike_is_idempotent(self):
        self.like(liked=True)
        self.assertFalse(self.like(liked=False).get_json()['liked'])
        self.assertFalse(self.like(liked=False).get_json()['liked'])
        self.assertEqual(self.client.get('/api/likes').get_json(), {})

    def test_like_from_previous_location_updates_current_location(self):
        self.aliases = {'House/song.mp3': 'Other/song.mp3'}
        self.stats = {'House/song.mp3': {'liked': True}, 'Other/song.mp3': {'liked': True}}
        self.like(liked=False)
        self.assertFalse(self.stats['Other/song.mp3']['liked'])
        self.assertEqual(self.client.get('/api/likes').get_json(), {})

    def test_web_toggle_is_compatible(self):
        self.assertTrue(self.like().get_json()['liked'])
        self.assertFalse(self.like().get_json()['liked'])

    def test_rejects_invalid_state_without_mutating_stats(self):
        for invalid in ['true', 1, None, []]:
            self.assertEqual(self.like(liked=invalid).status_code, 400)
        self.assertEqual(self.stats, {})

    def test_save_preserves_counts_and_other_folders(self):
        self.stats = {'House/song.mp3': {'count': 12, 'last_played': 42},
                      'Techno/song.mp3': {'liked': True, 'count': 3}}
        self.like(liked=True)
        self.assertEqual(self.stats['House/song.mp3']['count'], 12)
        self.assertEqual(self.stats['House/song.mp3']['last_played'], 42)
        self.assertTrue(self.stats['Techno/song.mp3']['liked'])


if __name__ == '__main__':
    unittest.main()
