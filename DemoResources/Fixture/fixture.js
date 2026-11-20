// 使用 SNCK v1 协议联调 iOS Bridge。
'use strict';

const pending = new Map();
let sequence = 0;
const element = id => document.getElementById(id);

function log(value) {
  element('log').textContent = `${JSON.stringify(value, null, 2)}\n${element('log').textContent}`.slice(0, 7000);
}

function formatTime(milliseconds) {
  const seconds = Math.floor(milliseconds / 1000);
  const minutes = Math.floor(seconds / 60).toString().padStart(2, '0');
  return `${minutes}:${(seconds % 60).toString().padStart(2, '0')}`;
}

function render(playback) {
  element('chapter').textContent = playback.item?.title || '尚未设置队列';
  element('state').textContent = playback.state;
  element('time').textContent = `${formatTime(playback.positionMs)} / ${playback.durationMs ? formatTime(playback.durationMs) : '--:--'}`;
  element('progress').max = playback.durationMs || 1;
  element('progress').value = playback.positionMs;
  element('seek').max = playback.durationMs || 4000;
  element('seek').value = playback.positionMs;

  const timer = playback.timer;
  const timerText = {
    OFF: '未开启',
    AFTER_DURATION: `${Math.ceil(timer.remainingMs / 1000)} 秒后关闭`,
    AFTER_ITEMS: `剩余 ${timer.remainingCount} 个`
  };
  element('timerState').textContent = timerText[timer.mode];
}

function renderIdentity(userState) {
  element('identity').textContent = userState.user ? `用户：${userState.user.id}` : '游客';
}

window.xhWebJSBridge = { nativeCallJS({actionName, parameters}) {
  const callback = pending.get(actionName);
  if (callback) {
    pending.delete(actionName);
    clearTimeout(callback.timeout);
    if (parameters && typeof parameters.code === 'number') {
      callback.reject(parameters);
    } else {
      callback.resolve(parameters);
    }
    return;
  }
  if (actionName === 'snckUserChanged') {
    renderIdentity(parameters);
  } else if (actionName.startsWith('snckAudio')) {
    render(parameters);
    if (actionName === 'snckAudioError') {
      log(parameters.error);
    }
  }
} };

function call(actionName, parameters = {}) {
  const callbackActionName = `snck_cb_fixture_${++sequence}`;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(callbackActionName);
      reject({code:4105, message:`${actionName} 回包超时`});
    }, actionName === 'xhSnckShare' ? 125000 : 15000);
    pending.set(callbackActionName, {resolve, reject, timeout});
    window.xhAppJSBridge.JSCallNative(JSON.stringify({actionName, parameters, callbackActionName}));
  });
}

function run(actionName, parameters) {
  return call(actionName, parameters).then(result => {
    if (result?.state) {
      render(result);
    }
    if (result) {
      log(result);
    }
  }).catch(log);
}

function loadQueue(url) {
  return call('xhSnckAudioSetQueue', {items:[{id:'fixture', title:'联调音频', url}]});
}

document.querySelectorAll('[data-action]').forEach(button => {
  button.addEventListener('click', () => run(button.dataset.action));
});
element('load').addEventListener('click', () => loadQueue(element('audioURL').value.trim()).then(render).catch(log));
element('seek').addEventListener('change', event => run('xhSnckAudioSeekTo', {positionMs:Number(event.target.value)}));
element('share').addEventListener('click', () => run('xhSnckShare', {
  title:'听书集成验证', link:'https://www.xinhuanet.com/', description:'验证宿主分享'
}));
element('applyTimer').addEventListener('click', () => {
  const value = element('timer').value;
  let parameters = {mode:'OFF'};
  if (value === 'custom' || Number(value) <= 3) {
    parameters = {mode:'AFTER_ITEMS', count:value === 'custom' ? Number(element('count').value) : Number(value)};
  } else if (value !== 'off') {
    parameters = {mode:'AFTER_DURATION', durationMs:Number(value)};
  }
  run('xhSnckAudioSetTimer', parameters);
});

call('xhSnckReady').then(ready => {
  renderIdentity(ready.userState);
  render(ready.playback);
}).catch(log);
