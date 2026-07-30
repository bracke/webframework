// Server-Sent Events demo client: subscribe to /events and list each event.
(function () {
  "use strict";
  var log = document.getElementById("sse-log");
  function add(text) {
    var li = document.createElement("li");
    li.textContent = text;
    log.appendChild(li);
  }
  var es = new EventSource("/events");
  es.addEventListener("tick", function (e) {
    add(e.data);
  });
  es.addEventListener("end", function (e) {
    add("— " + e.data + " —");
    es.close();
  });
  es.onerror = function () {
    add("(disconnected)");
    es.close();
  };
})();
