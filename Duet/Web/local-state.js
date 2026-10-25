(() => {
  const key = 'duet.preview.preferences.v1';
  let state = window.duetInitialState || null;
  if (!state) {
    try { state = JSON.parse(localStorage.getItem(key) || 'null'); } catch { }
  }
  const native = window.webkit?.messageHandlers?.duet;
  document.documentElement.dataset.nativeShell = String(Boolean(native));
  window.openai = {
    get widgetState() { return state; },
    async setWidgetState(snapshot) {
      const json = JSON.stringify(snapshot);
      if (new TextEncoder().encode(json).length > 16 * 1024) throw Error('偏好设置过大');
      state = snapshot;
      try { localStorage.setItem(key, json); } catch { }
      native?.postMessage({ type: 'persist', snapshot });
    }
  };
})();
