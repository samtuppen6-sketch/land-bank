(() => {
  'use strict';

  let deferredPrompt = null;

  function syncConnectionState() {
    const live = document.querySelector('.live');
    if (!live) return;
    if (navigator.onLine) {
      live.textContent = '● Live intelligence';
      live.style.color = '#89b69d';
    } else {
      live.textContent = '● Offline — reconnect for live data';
      live.style.color = '#efb66a';
    }
  }

  function installButton() {
    const top = document.querySelector('.top');
    if (!top || top.querySelector('.pwaInstall') || !deferredPrompt) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'pwaInstall';
    button.textContent = 'Install app';
    button.addEventListener('click', async () => {
      const prompt = deferredPrompt;
      if (!prompt) return;
      deferredPrompt = null;
      button.remove();
      await prompt.prompt();
      await prompt.userChoice.catch(() => null);
    });
    top.appendChild(button);
  }

  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault();
    deferredPrompt = event;
    installButton();
  });

  window.addEventListener('appinstalled', () => {
    deferredPrompt = null;
    document.querySelector('.pwaInstall')?.remove();
  });

  window.addEventListener('online', syncConnectionState);
  window.addEventListener('offline', syncConnectionState);
  syncConnectionState();

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sales-pro-sw.js').catch(error => {
      console.warn('LandBank service worker registration failed', error);
    });
  }
})();
