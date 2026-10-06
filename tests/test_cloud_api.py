import hashlib
import json
import tempfile
import threading
import unittest
from pathlib import Path
from flask import Flask
from cloud_api import register_cloud_api

class CloudTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'downloads' / 'Music').mkdir(parents=True)
        self.app = Flask(__name__)
        self.canonical = register_cloud_api(self.app, self.root, threading.Lock())
        self.ios = self.app.test_client()
        self.mac = self.app.test_client()
    def tearDown(self):
        self.temp.cleanup()
    def upload(self, client, path, audio):
        session = client.post('/api/cloud/upload').json['id']
        self.assertEqual(client.put('/api/cloud/upload/'+session, query_string={'path':path}, data=audio).status_code, 200)
        response = client.post('/api/cloud/upload/'+session+'/commit')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(client.post('/api/cloud/upload/'+session+'/commit').json, response.json)
        return response.json
    def test_mac_upload_ios_download_and_undo_across_restart(self):
        file = self.root / 'downloads/Music/song.wav';file.write_bytes(b'previous')
        result = self.upload(self.mac, 'Music/song.wav', b'updated')
        manifest = self.ios.get('/api/cloud/manifest').json
        self.assertEqual(manifest['tracks'][0]['hash'], hashlib.sha256(b'updated').hexdigest())
        with self.ios.get('/api/cloud/blob/'+manifest['tracks'][0]['hash']) as response:
            self.assertEqual(response.data,b'updated')
        app = Flask('restart');register_cloud_api(app, self.root, threading.Lock())
        client = app.test_client()
        self.assertEqual(client.post('/api/cloud/undo/'+result['id']).status_code, 200)
        self.assertEqual(file.read_bytes(), b'previous')
    def test_conflict_and_expired_undo_never_overwrite(self):
        first = self.upload(self.mac, 'Music/song.wav', b'first')
        self.upload(self.ios, 'Music/song.wav', b'second')
        self.assertEqual(self.mac.post('/api/cloud/undo/'+first['id']).status_code,409)
        file = self.root / '.wave-cloud/operations' / (first['id']+'.json')
        value = json.loads(file.read_text());value['expires']=0;file.write_text(json.dumps(value))
        self.assertEqual(self.mac.post('/api/cloud/undo/'+first['id']).status_code,409)
        self.assertEqual((self.root/'downloads/Music/song.wav').read_bytes(),b'second')
    def test_relocation_preserves_like_and_undo_location(self):
        self.upload(self.mac, 'Music/song.wav', b'song')
        (self.root/'downloads/Other').mkdir()
        (self.root/'play_stats.json').write_text(json.dumps({'Music/song.wav':{'liked':True,'count':4}}))
        result = self.ios.post('/api/cloud/relocate',json={'track':'Music/song.wav','folder':'Other'})
        self.assertEqual(result.status_code,200)
        self.assertFalse((self.root/'downloads/Music/song.wav').exists())
        self.assertEqual(self.canonical('Music/song.wav'),'Other/song.wav')
        self.assertTrue(json.loads((self.root/'play_stats.json').read_text())['Other/song.wav']['liked'])
        self.assertEqual(self.mac.post('/api/cloud/undo/'+result.json['id']).status_code,200)
        self.assertTrue((self.root/'downloads/Music/song.wav').exists())
        self.assertFalse((self.root/'downloads/Other/song.wav').exists())
        self.assertEqual(self.canonical('Other/song.wav'),'Music/song.wav')
    def test_invalid_paths_and_symlinks(self):
        session=self.mac.post('/api/cloud/upload').json['id']
        for path in ['../bad.wav','/bad.wav','Music/../../bad.wav','Music/.secret.wav','Music/file.txt','Music//song.wav']:
            self.assertEqual(self.mac.put('/api/cloud/upload/'+session, query_string={'path':path},data=b'a').status_code,400,path)
        outside=self.root/'outside';outside.mkdir();(self.root/'downloads/Linked').symlink_to(outside)
        self.assertEqual(self.mac.put('/api/cloud/upload/'+session,query_string={'path':'Linked/song.wav'},data=b'a').status_code,400)
    def test_manifest_does_not_duplicate_existing_library(self):
        (self.root/'downloads/Music/song.wav').write_bytes(b'existing')
        manifest=self.mac.get('/api/cloud/manifest').json
        self.assertEqual(list((self.root/'.wave-cloud/blobs').iterdir()),[])
        with self.ios.get('/api/cloud/blob/'+manifest['tracks'][0]['hash']) as response:
            self.assertEqual(response.data,b'existing')
    def test_upload_conflict_between_devices(self):
        session=self.mac.post('/api/cloud/upload').json['id']
        self.mac.put('/api/cloud/upload/'+session,query_string={'path':'Music/song.wav'},data=b'mac')
        self.upload(self.ios,'Music/song.wav',b'ios')
        self.assertEqual(self.mac.post('/api/cloud/upload/'+session+'/commit').status_code,409)
        self.assertEqual((self.root/'downloads/Music/song.wav').read_bytes(),b'ios')
if __name__=='__main__':unittest.main()
