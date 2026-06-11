-- ============================================================
-- ACCOR EBS Finance Bot - APEX Page 2 Full Setup
-- Application ID: 43171
-- Run in: APEX SQL Workshop > SQL Commands (one block at a time)
-- ============================================================

-- BLOCK 1: Add Page 2 Inline CSS + JavaScript
-- Go to: App Builder > App 43171 > Page 2 > Right panel > CSS > Inline
-- Paste the CSS below into the Inline CSS field and Save

/* ===== CHAT WORKSPACE CSS ===== 
.chat-feed{height:420px;overflow-y:auto;padding:16px;background:#0d1117;border-radius:12px;display:flex;flex-direction:column;gap:12px;margin-bottom:16px}
.chat-msg-user{align-self:flex-end;background:#1f6feb;color:#fff;padding:10px 16px;border-radius:18px 18px 4px 18px;max-width:70%;word-break:break-word}
.chat-msg-bot{align-self:flex-start;background:#161b22;color:#e6edf3;padding:10px 16px;border-radius:18px 18px 18px 4px;max-width:80%;border:1px solid #30363d}
.chat-msg-bot table{border-collapse:collapse;width:100%;font-size:.85em}
.chat-msg-bot td,.chat-msg-bot th{border:1px solid #30363d;padding:6px 10px}
.chat-msg-bot th{background:#21262d}
#P2_USER_MESSAGE{background:#161b22;color:#e6edf3;border:1px solid #30363d;border-radius:8px;resize:none;width:100%;padding:10px}
.chat-chip-bar{margin-bottom:8px}
.chat-chip{display:inline-block;padding:5px 14px;margin:3px;background:#21262d;color:#58a6ff;border-radius:20px;cursor:pointer;font-size:.82em;border:1px solid #30363d}
.chat-chip:hover{background:#1f6feb;color:#fff}
.approval-box{background:#161b22;border:1px solid #f85149;border-radius:12px;padding:16px;margin-top:8px;display:none}
.approval-box.visible{display:block}
*/

-- BLOCK 2: JavaScript to paste in Page 2 > JavaScript > Function and Global Variable Declaration
/*
function sendChatMessage() {
  var msg = apex.item('P2_USER_MESSAGE').getValue();
  if (!msg || !msg.trim()) { 
    apex.message.showErrors([{type:'error',location:'page',message:'Please type a message first.'}]); 
    return; 
  }
  apex.server.process('PROCESS_CHAT', {
    pageItems: '#P2_USER_MESSAGE,#P2_PROPERTY_ID',
    x01: msg
  }, {
    dataType: 'json',
    success: function(data) {
      if(data.status === 'success') {
        // Reload the chat feed region
        apex.region('CHAT_FEED').refresh();
        apex.item('P2_USER_MESSAGE').setValue('');
        // Check if approval needed
        if(data.requires_approval === true) {
          apex.item('P2_APPROVAL_PAYLOAD').setValue(JSON.stringify(data.approval_payload || {}));
          $('#approval-box').addClass('visible');
          $('#approval-invoice-id').text(data.approval_payload ? data.approval_payload.invoice_id : '');
        } else {
          $('#approval-box').removeClass('visible');
        }
      } else {
        apex.message.showErrors([{type:'error',location:'page',message: data.message || 'Chat error.'}]);
      }
    },
    error: function() {
      apex.message.showErrors([{type:'error',location:'page',message:'Connection error. Please try again.'}]);
    }
  });
}
function sendChip(text) {
  apex.item('P2_USER_MESSAGE').setValue(text);
  sendChatMessage();
}
function confirmPayment() {
  apex.item('P2_USER_MESSAGE').setValue('CONFIRM');
  sendChatMessage();
}
*/
