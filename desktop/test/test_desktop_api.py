import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from flask import Flask

spec = importlib.util.spec_from_file_location('desktop_api', Path(__file__).resolve().parents[2] / 'desktop_api.py')
api = importlib.util.module_from_spec(spec)
spec.loader.exec_module(api)

class DesktopAPITest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wave-api-test-')
        self.root = Path(self.temp.name)
        (self.root/'downloads'/'Album').mkdir(parents=True)
        (self.root/'downloads'/'Album'/'song.mp3').write_bytes(b'original audio')
        (self.root/'.env').write_text('SPOTIFY_CLIENT_ID=test-client\nSPOTIFY_CLIENT_SECRET=test-secret\n')
        self.app = Flask(__name__)
        api.register_desktop_api(self.app, self.root)
        self.client = self.app.test_client()
    def tearDown(self):
        self.temp.cleanup()
    def test_organization_changes_current_library_without_deleting_audio(self):
        response = self.client.post('/api/desktop/state', json={'action':'hidden','paths':['Album/song.mp3'],'hidden':True})
        self.assertEqual(response.status_code,200)
        self.assertEqual(response.json['hidden'],['Album/song.mp3'])
        self.assertEqual((self.root/'downloads'/'Album'/'song.mp3').read_bytes(),b'original audio')
        response = self.client.post('/api/desktop/state',json={'action':'order','scope':'Album','paths':['Album/song.mp3']})
        self.assertEqual(response.status_code,200)
        stored = json.loads((self.root/'downloads'/'.wave-library.json').read_text())
        self.assertEqual(stored['orders']['Album'],['Album/song.mp3'])
        self.assertEqual(self.client.post('/api/desktop/state',json={'action':'hidden','paths':['Album/song.mp3'],'hidden':False}).json['hidden'],[])
    def test_rejects_traversal(self):
        for operation in [{'action':'hidden','paths':['../private.mp3'],'hidden':True},{'action':'order','scope':'../outside','paths':[]}]:
            self.assertEqual(self.client.post('/api/desktop/state',json=operation).status_code,400)
    def test_token_is_temporary_cached_and_never_exposes_secret(self):
        response = Mock(ok=True,status_code=200)
        response.json.return_value={'access_token':'temporary-catalog-token','expires_in':3600}
        with patch.object(api.requests,'post',return_value=response) as post:
            first=self.client.post('/api/spotify/search-token')
            second=self.client.post('/api/spotify/search-token')
        self.assertEqual(first.status_code,200)
        self.assertEqual(second.json['access_token'],'temporary-catalog-token')
        self.assertEqual(post.call_count,1)
        self.assertEqual(first.headers['Cache-Control'],'no-store')
        self.assertNotIn('test-secret',first.get_data(as_text=True))
        self.assertEqual(self.client.get('/api/spotify/status').json['configured'],True)
    def test_token_requests_are_rate_limited(self):
        response=Mock(ok=True,status_code=200)
        response.json.return_value={'access_token':'temporary','expires_in':3600}
        with patch.object(api.requests,'post',return_value=response):
            for _ in range(20): self.assertEqual(self.client.post('/api/spotify/search-token').status_code,200)
            self.assertEqual(self.client.post('/api/spotify/search-token').status_code,429)

if __name__ == '__main__': unittest.main()
