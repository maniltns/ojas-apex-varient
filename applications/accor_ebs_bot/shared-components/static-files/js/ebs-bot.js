/* ============================================================
 * Grandback (EBS) Finance Bot — chat client
 * Talks to GRANDBACK_BOT_API_PKG via three AJAX callbacks:
 *   LOAD_BOOTSTRAP, PROCESS_CHAT, CANCEL_APPROVAL
 * ============================================================ */
(function () {
  'use strict';

  // Markup-allowlist sanitiser — bot replies are HTML, but only this set.
  var ALLOWED_TAGS = {
    'A': ['href','target','rel'],
    'BR': [], 'CODE': [], 'DD': [], 'DIV': ['class','data-status','data-role'],
    'DL': ['class'], 'DT': [], 'EM': [], 'H3': ['class'], 'H4': ['class'],
    'LI': [], 'OL': [], 'P': ['class'], 'SPAN': ['class','data-status'],
    'STRONG': [], 'SUB': [], 'SUP': [],
    'TABLE': ['class'], 'TBODY': [], 'TD': ['class','data-status'],
    'TFOOT': [], 'TH': ['class','scope','data-status'], 'THEAD': [], 'TR': ['class','data-status'],
    'UL': []
  };
  function sanitize(html) {
    var doc = new DOMParser().parseFromString('<div>' + html + '</div>', 'text/html');
    var root = doc.body.firstElementChild;
    walk(root);
    return root.innerHTML;

    function walk(node) {
      var children = Array.from(node.children);
      children.forEach(function (child) {
        var tag = child.tagName;
        if (!ALLOWED_TAGS.hasOwnProperty(tag)) {
          // Replace disallowed tag with its text content.
          child.replaceWith(document.createTextNode(child.textContent));
          return;
        }
        var allowedAttrs = ALLOWED_TAGS[tag];
        Array.from(child.attributes).forEach(function (attr) {
          if (allowedAttrs.indexOf(attr.name) === -1) {
            child.removeAttribute(attr.name);
          }
          if (attr.name === 'href' && /^\s*javascript:/i.test(attr.value)) {
            child.removeAttribute('href');
          }
        });
        walk(child);
      });
    }
  }

  function el(tag, attrs, text) {
    var node = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) {
      if (k === 'class') node.className = attrs[k];
      else if (k === 'html') node.innerHTML = sanitize(attrs[k]);
      else node.setAttribute(k, attrs[k]);
    });
    if (text != null) node.textContent = text;
    return node;
  }

  function fmtTime(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  var EbsBot = {
    state: {
      thread_id: null,
      role: null,
      user: null,
      pendingApproval: null,
      sending: false,
      history: []
    },

    init: function () {
      this.shell      = document.getElementById('ebs-shell');
      if (!this.shell) return;

      this.feed       = this.shell.querySelector('.ebs-feed');
      this.input      = this.shell.querySelector('.ebs-input');
      this.sendBtn    = this.shell.querySelector('.ebs-send');
      this.typing     = this.shell.querySelector('.ebs-typing');
      this.propSelect = this.shell.querySelector('.ebs-property__select');
      this.userSlot   = this.shell.querySelector('[data-user-name]');
      this.roleSlot   = this.shell.querySelector('[data-role-pill]');
      this.modal      = document.getElementById('ebs-modal');

      document.body.classList.add('ebs-shell-active');

      this.bindEvents();
      this.bootstrap();
    },

    bindEvents: function () {
      var self = this;

      this.sendBtn.addEventListener('click', function () { self.send(); });
      this.input.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          self.send();
        }
      });
      this.input.addEventListener('input', function () {
        self.input.style.height = 'auto';
        self.input.style.height = Math.min(self.input.scrollHeight, 180) + 'px';
      });

      this.shell.querySelectorAll('.ebs-chip').forEach(function (chip) {
        chip.addEventListener('click', function () {
          self.input.value = chip.dataset.prompt || chip.textContent.trim();
          self.input.focus();
          self.send();
        });
      });

      if (this.modal) {
        this.modal.querySelector('[data-action="confirm"]').addEventListener('click', function () {
          self.confirmApproval();
        });
        this.modal.querySelector('[data-action="cancel"]').addEventListener('click', function () {
          self.cancelApproval();
        });
        document.addEventListener('keydown', function (e) {
          if (e.key === 'Escape' && self.modal.classList.contains('is-on')) {
            self.cancelApproval();
          }
        });
      }
    },

    bootstrap: function () {
      var self = this;
      apex.server.process('LOAD_BOOTSTRAP', {}, {
        dataType: 'json',
        success: function (data) {
          self.state.thread_id = data.thread_id;
          self.state.role      = data.user && data.user.role;
          self.state.user      = data.user;

          if (self.shell && self.state.role) {
            self.shell.dataset.role = self.state.role;
          }
          if (self.userSlot && data.user) {
            self.userSlot.textContent = data.user.name || data.user.email || '';
          }
          if (self.roleSlot && data.user) {
            self.roleSlot.textContent = (data.user.role || '').replace('_', ' ');
            self.roleSlot.dataset.role = data.user.role || '';
          }

          self.renderProperties(data.properties || []);
          self.renderHistory(data.recent || []);
        },
        error: function () {
          self.appendBot('<div class="ebs-alert ebs-alert--danger"><strong>Connection error.</strong> Could not load chat session.</div>');
        }
      });
    },

    renderProperties: function (props) {
      if (!this.propSelect) return;
      this.propSelect.innerHTML = '';
      if (props.length === 0) {
        var o = document.createElement('option');
        o.value = ''; o.textContent = '— No accessible properties —';
        this.propSelect.appendChild(o);
        return;
      }
      props.forEach(function (p) {
        var o = document.createElement('option');
        o.value = p.id;
        o.textContent = p.name + ' · ' + (p.city || '') + ' · ' + (p.currency || '');
        this.propSelect.appendChild(o);
      }, this);
    },

    renderHistory: function (recent) {
      if (recent.length === 0) {
        this.appendBot(this.welcomeMessage());
        return;
      }
      recent.forEach(function (m) {
        if (m.role === 'user') this.appendUser(m.content, m.ts);
        else this.appendBot(m.content, m.ts);
      }, this);
    },

    welcomeMessage: function () {
      var nameBit = this.state.user && this.state.user.name
        ? '<strong>' + this.state.user.name + '</strong>, '
        : '';
      return '<p>' + nameBit + 'welcome to the Grandback (EBS) Finance Bot.</p>'
           + '<p>Ask about <code>AP aging</code>, <code>AR aging</code>, <code>overdue invoices</code>, '
           + '<code>GL balances</code>, <code>journals</code>, '
           + '<code>property summary</code>, or <code>show vendor &lt;name&gt;</code>. '
           + 'Managers can also <code>approve payment for ap_inv_NNNN</code>.</p>';
    },

    appendUser: function (content, ts) {
      var initials = (this.state.user && this.state.user.name || '?')
        .split(' ').map(function (s) { return s[0]; }).join('').slice(0,2).toUpperCase();
      var msg = el('div', { class: 'ebs-msg ebs-msg--user' });
      msg.appendChild(el('div', { class: 'ebs-msg__avatar' }, initials));
      var body = el('div', { class: 'ebs-msg__body' });
      var meta = el('div', { class: 'ebs-msg__meta' });
      meta.appendChild(el('span', { class: 'ebs-msg__role' }, 'You'));
      if (ts) meta.appendChild(el('span', { class: 'ebs-msg__time' }, fmtTime(ts)));
      body.appendChild(meta);
      var c = el('div', { class: 'ebs-msg__content' });
      c.textContent = content;
      body.appendChild(c);
      msg.appendChild(body);
      this.feed.appendChild(msg);
      this.scrollToBottom();
    },

    appendBot: function (html, ts) {
      var msg = el('div', { class: 'ebs-msg ebs-msg--bot' });
      msg.appendChild(el('div', { class: 'ebs-msg__avatar' }, 'AI'));
      var body = el('div', { class: 'ebs-msg__body' });
      var meta = el('div', { class: 'ebs-msg__meta' });
      meta.appendChild(el('span', { class: 'ebs-msg__role' }, 'EBS Finance Bot'));
      if (ts) meta.appendChild(el('span', { class: 'ebs-msg__time' }, fmtTime(ts)));
      body.appendChild(meta);
      body.appendChild(el('div', { class: 'ebs-msg__content', html: html }));
      msg.appendChild(body);
      this.feed.appendChild(msg);
      this.scrollToBottom();
    },

    scrollToBottom: function () {
      var feed = this.feed;
      requestAnimationFrame(function () { feed.scrollTop = feed.scrollHeight; });
    },

    setTyping: function (on) {
      if (!this.typing) return;
      this.typing.classList.toggle('is-on', !!on);
      if (on) this.scrollToBottom();
    },

    send: function (override) {
      var msg = override != null ? override : this.input.value.trim();
      if (!msg || this.state.sending) return;

      var prop = this.propSelect ? this.propSelect.value : '';

      this.appendUser(msg, new Date().toISOString());
      this.input.value = '';
      this.input.style.height = 'auto';
      this.state.sending = true;
      this.sendBtn.disabled = true;
      this.setTyping(true);

      var self = this;
      apex.server.process('PROCESS_CHAT',
        { x01: msg, x02: prop },
        {
          dataType: 'json',
          success: function (data) {
            self.setTyping(false);
            self.state.sending = false;
            self.sendBtn.disabled = false;

            if (!data || data.status === 'error') {
              self.appendBot('<div class="ebs-alert ebs-alert--danger"><strong>Server error.</strong> ' +
                (data && data.message ? data.message : 'Unknown failure.') +
                '</div>');
              return;
            }

            self.appendBot(data.reply || '', new Date().toISOString());

            if (data.requires_approval && data.approval_payload) {
              self.openApprovalModal(data.approval_payload);
            }
          },
          error: function () {
            self.setTyping(false);
            self.state.sending = false;
            self.sendBtn.disabled = false;
            self.appendBot('<div class="ebs-alert ebs-alert--danger"><strong>Connection error.</strong> Please retry.</div>');
          }
        }
      );
    },

    openApprovalModal: function (payload) {
      if (!this.modal) return;
      this.state.pendingApproval = payload;
      var amount = (payload.amount || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      this.modal.querySelector('[data-slot="invoice-id"]').textContent = payload.invoice_id || '—';
      this.modal.querySelector('[data-slot="invoice-number"]').textContent = payload.invoice_number || '—';
      this.modal.querySelector('[data-slot="amount"]').textContent = amount + ' ' + (payload.currency || '');
      this.modal.classList.add('is-on');
      this.modal.querySelector('[data-action="confirm"]').focus();
    },

    closeApprovalModal: function () {
      if (this.modal) this.modal.classList.remove('is-on');
      this.state.pendingApproval = null;
    },

    confirmApproval: function () {
      this.closeApprovalModal();
      this.send('CONFIRM');
    },

    cancelApproval: function () {
      var self = this;
      apex.server.process('CANCEL_APPROVAL', {}, {
        dataType: 'json',
        complete: function () {
          self.appendBot('<div class="ebs-alert ebs-alert--neutral">Approval cancelled. No DML executed.</div>');
          self.closeApprovalModal();
        }
      });
    }
  };

  if (window.apex && apex.jQuery) {
    apex.jQuery(function () { EbsBot.init(); });
  } else {
    document.addEventListener('DOMContentLoaded', function () { EbsBot.init(); });
  }

  window.EbsBot = EbsBot;
})();
