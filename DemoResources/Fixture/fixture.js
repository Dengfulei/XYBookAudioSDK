// 本地播放联调页：使用已确认的标准消息和方法名；用户资料由宿主提供，播放状态由原生会话持有。
'use strict';
const pending = new Map();
let sequence = 0;
let identityRevision = 0;
const identityEvent = 'onBookAudioUserIdentityChange';
const element = id => document.getElementById(id);
const log = value => { element('log').textContent = `${JSON.stringify(value, null, 2)}\n${element('log').textContent}`.slice(0, 7000); };
const time = milliseconds => { const seconds = Math.floor(milliseconds / 1000); return `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${(seconds % 60).toString().padStart(2, '0')}`; };
function render(snapshot) {
  element('chapter').textContent = snapshot.chapterTitle || '尚未设置队列';
  element('state').textContent = `${snapshot.state} · ${snapshot.rate}×${snapshot.reason ? ` · ${snapshot.reason}` : ''}`;
  element('time').textContent = `${time(snapshot.positionMs)} / ${snapshot.durationMs ? time(snapshot.durationMs) : '--:--'}`;
  element('progress').max = snapshot.durationMs || 1; element('progress').value = snapshot.positionMs;
  element('seek').max = snapshot.durationMs || 4000; element('seek').value = snapshot.positionMs;
  const timer = snapshot.sleepTimer;
  element('timerState').textContent = timer.mode === 'off' ? '未开启' : timer.mode === 'duration' ? `${Math.ceil(timer.remainingMs / 1000)} 秒后关闭` : `剩余 ${timer.remainingCount} 个 · ${timer.estimatedRemainingMs === undefined ? '时长待获取' : `${Math.ceil(timer.estimatedRemainingMs / 60000)} 分钟`}`;
}
// 身份事件仅更新宿主登录展示；登录状态不作为购买权益，也不自动重新装载章节或开始播放。
function renderIdentity(identity) {
  element('identity').textContent = identity.isLoggedIn ? `用户：${identity.userId}` : '游客';
}
// 先订阅再查询以衔接页面关闭期间的账号变化；新事件到达后，不用更早的查询结果覆盖当前展示。
async function refreshIdentity() {
  const revision = identityRevision;
  const profile = await call('xhGetUserInfo', {goLogin:false, useTicket:false});
  const identity = {isLoggedIn:!!profile.id, userId:profile.id || ''};
  if (revision === identityRevision) {
    renderIdentity(identity);
  }
  return identity;
}
window.xhWebJSBridge = { nativeCallJS(envelope) {
  if (envelope.actionName === identityEvent) {
    identityRevision++;
    renderIdentity(envelope.parameters);
    log(envelope);
    return;
  }
  if (envelope.actionName === 'onBookAudioPlaybackChange') { render(envelope.parameters); return; }
  const callback = pending.get(envelope.actionName);
  if (callback) { pending.delete(envelope.actionName); clearTimeout(callback.timeout); callback.resolve(envelope.parameters); }
  else {
    log(envelope);
  }
} };
// 只封装需要成功结果的查询；callbackActionName 由 H5 自行生成，不向原生附加版本或请求 ID。
// 业务失败通过 onBookAudioError 展示；该事件当前只有 code/message，不能据此猜测并发请求归属。
function call(actionName, parameters = {}) {
  const callbackActionName = `fixture-callback-${++sequence}`;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pending.delete(callbackActionName);
      reject({code:'TIMEOUT', message:`${actionName} 未收到成功回调，请检查错误事件或页面状态`});
    }, 190000);
    pending.set(callbackActionName, {resolve, timeout});
    window.xhAppJSBridge.JSCallNative(JSON.stringify({actionName, parameters, callbackActionName}));
  });
}
// 按钮命令不等待成功结果；页面已经订阅状态／错误事件，避免将某个错误错误关联到并发命令。
function run(actionName, parameters = {}) {
  log({actionName, parameters});
  window.xhAppJSBridge.JSCallNative(JSON.stringify({actionName, parameters}));
}
async function loadQueue(paid) {
  const identity = await refreshIdentity();
  const chapters = [1,2,3].map(index => ({chapterId:`chapter-${index}`, title:`第 ${index} 章 · 本地音频`, requiresLogin:paid && index > 1, durationMs:4000,
    ...(!paid || index === 1 || identity.isLoggedIn ? {audioURL:new URL(`chapter-${index}.wav`, location.href).href} : {})}));
  await call('xhBookAudioSetQueue', {bookId:paid ? 'local-paid' : 'local-free', title:'本地听书验证', chapters, chapterId:'chapter-1', positionMs:0});
}
document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', () => run(button.dataset.action)));
// 标准登录只负责打开宿主页面，没有业务回调；身份展示由身份变更事件刷新。
element('login').addEventListener('click', () => {
  window.xhAppJSBridge.JSCallNative(JSON.stringify({actionName:'xhGoLogin', parameters:{}}));
});
element('free').addEventListener('click', () => loadQueue(false).catch(log));
element('paid').addEventListener('click', () => loadQueue(true).catch(log));
element('rate').addEventListener('change', event => run('xhBookAudioSetRate', {rate:Number(event.target.value)}));
element('seek').addEventListener('change', event => run('xhBookAudioSeekTo', {positionMs:Number(event.target.value)}));
element('share').addEventListener('click', () => run('xhShowShareMenu', {title:'听书集成验证', link:'https://www.xinhuanet.com/', desc:'本地页面验证宿主链接分享'}));
element('applyTimer').addEventListener('click', () => {
  const value = element('timer').value;
  if (value === 'off') {
    return run('xhBookAudioCancelSleepTimer');
  }
  run('xhBookAudioSetSleepTimer', ['1','2','3','custom'].includes(value) ? {mode:'trackCount', count:value === 'custom' ? Number(element('count').value) : Number(value)} : {mode:'duration', durationMs:Number(value)});
});
// 重新打开页面时只查询状态并订阅事件，保留现有队列和正在运行的定时关闭任务。
async function connect() {
  log(await call('xhBookAudioGetCapabilities'));
  await call('xhBookAudioSubscribe');
  await refreshIdentity();
  render(await call('xhBookAudioGetSnapshot'));
}
connect().catch(log);
