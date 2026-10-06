const {contextBridge,ipcRenderer} = require('electron');
const invoke = name => (...args)=>ipcRenderer.invoke(`wave:${name}`,...args);
const on = channel => callback=>ipcRenderer.on(`wave:${channel}`,(_event,value)=>callback(value));
contextBridge.exposeInMainWorld('wave',{
 cloudUpload:invoke('cloud-upload'),cloudDownload:invoke('cloud-download'),cloudUndoLocal:invoke('cloud-undo-local'),cloudHistory:invoke('cloud-history'),cloudUndo:invoke('cloud-undo'),likes:invoke('likes'),like:invoke('like'),relocate:invoke('relocate'),
 windowControl:invoke('window-control'),volumes:invoke('volumes'),openVolume:invoke('open-volume'),artwork:invoke('artwork'),waveformAudio:invoke('waveform-audio'),state:invoke('state'),switchSource:invoke('source'),chooseFolder:invoke('folder'),refresh:invoke('refresh'),saveServer:invoke('server'),
 serverFolders:invoke('server-folders'),serverTracks:invoke('server-tracks'),editState:invoke('edit-state'),played:invoke('played'),
 clipboardCommand:invoke('clipboard-command'),copy:invoke('copy'),removeTray:invoke('tray-remove'),paste:invoke('paste'),reveal:invoke('reveal'),
 spotifyStatus:invoke('spotify-status'),spotifySearch:invoke('spotify-search'),openSpotify:invoke('open-spotify'),
 onNavigate:on('navigate-request'),onSource:on('source-changed'),onTray:on('tray'),onRefresh:on('refresh-request'),onCopy:on('copy-request'),onPaste:on('paste-request'),onSelectAll:on('select-request')
});
