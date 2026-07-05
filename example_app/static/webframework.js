(function () {
  "use strict";

  var socket = null;

  function connect() {
    if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
      return;
    }
    var path = document.body.getAttribute("data-wf-ws") || "/ws";
    var scheme = window.location.protocol === "https:" ? "wss:" : "ws:";
    socket = new WebSocket(scheme + "//" + window.location.host + path);
    socket.addEventListener("open", function () {
      socket.send(JSON.stringify({ type: "hello", version: 1 }));
    });
    socket.addEventListener("message", function (event) {
      var message = null;
      try {
        message = JSON.parse(event.data);
      } catch (error) {
        return;
      }
      if (message.type === "patches" && Array.isArray(message.patches)) {
        applyPatches(message.patches);
      }
    });
  }

  function send(message) {
    message.version = 1;
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(message));
    }
  }

  function applyPatches(patches) {
    patches.forEach(function (patch) {
      var target = document.getElementById(patch.target);
      if (!target) {
        return;
      }
      if (patch.op === "replace_html") {
        if (!patch.force && target.contains(document.activeElement)) {
          return;
        }
        target.innerHTML = patch.value || "";
      } else if (patch.op === "set_text") {
        target.textContent = patch.value || "";
      } else if (patch.op === "set_attr") {
        target.setAttribute(patch.name, patch.value || "");
      } else if (patch.op === "remove_attr") {
        target.removeAttribute(patch.name);
      } else if (patch.op === "add_class") {
        target.classList.add(patch.name);
      } else if (patch.op === "remove_class") {
        target.classList.remove(patch.name);
      } else if (patch.op === "set_value") {
        target.value = patch.value || "";
      }
    });
  }

  document.addEventListener("click", function (event) {
    var element = event.target.closest("[data-wf-click]");
    if (element) {
      send({ type: "click", id: element.id, action: element.getAttribute("data-wf-click") });
    }
  });

  document.addEventListener("submit", function (event) {
    var form = event.target.closest("form[data-wf-submit]");
    var fields = {};
    if (!form) {
      return;
    }
    event.preventDefault();
    new FormData(form).forEach(function (value, key) {
      fields[key] = String(value);
    });
    send({ type: "submit", id: form.id, action: form.getAttribute("data-wf-submit"), fields: fields });
  });

  window.WebFramework = { connect: connect, applyPatches: applyPatches };
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", connect);
  } else {
    connect();
  }
}());
