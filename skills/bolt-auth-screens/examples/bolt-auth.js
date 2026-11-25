/*
 * js/bolt-auth.js — the password reveal button of Bolt's sign-in screens (bolt-auth-screens).
 *
 * A static file next to the theme's build output, loaded only by bolt-auth/_layout.twig: no
 * build step and no inline script, so the screens' Content-Security-Policy (script-src 'self',
 * Trusted Types) allows it. It writes no HTML. The buttons start hidden, so without JavaScript
 * nothing is offered that does not work.
 *
 * A revealed password is hidden again before the form is sent and when the page is left, so the
 * browser never stores it as plain text (form history, back/forward cache, screenshots of the
 * task switcher).
 */
(function () {
  'use strict';

  var pairs = [];

  function conceal(pair) {
    pair.input.type = 'password';
    pair.button.setAttribute('aria-pressed', 'false');
    pair.button.setAttribute('aria-label', pair.button.getAttribute('data-label-show'));
  }

  document.querySelectorAll('[data-ba-reveal]').forEach(function (button) {
    var input = document.getElementById(button.getAttribute('aria-controls'));
    if (!input || input.type !== 'password') {
      return;
    }

    var pair = { input: input, button: button };
    pairs.push(pair);
    button.hidden = false;
    button.addEventListener('click', function () {
      if (input.type === 'password') {
        input.type = 'text';
        button.setAttribute('aria-pressed', 'true');
        button.setAttribute('aria-label', button.getAttribute('data-label-hide'));
      } else {
        conceal(pair);
      }
    });
    if (input.form) {
      input.form.addEventListener('submit', function () {
        conceal(pair);
      });
    }
  });

  window.addEventListener('pagehide', function () {
    pairs.forEach(conceal);
  });
})();
