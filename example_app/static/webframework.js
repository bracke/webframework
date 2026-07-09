(function () {
  "use strict";

  // ============================================================================
  // CONFIGURATION
  // ============================================================================

  var socket = null;
  var reconnectAttempts = 0;
  var maxReconnectAttempts = 10;
  var reconnectBaseDelay = 1000; // 1 second base delay
  var reconnectMaxDelay = 30000; // 30 seconds max delay
  var reconnectTimeoutId = null;
  var isConnecting = false;

  // Adaptive reconnection strategy
  var reconnectionHistory = [];
  var lastReconnectTime = 0;
  var minReconnectInterval = 5000; // 5 seconds minimum between reconnect attempts

  // Connection quality monitoring
  var connectionStats = {
    totalConnections: 0,
    successfulConnections: 0,
    failedConnections: 0,
    lastConnectionTime: 0,
    lastDisconnectionTime: 0,
    totalMessagesSent: 0,
    totalMessagesReceived: 0,
    totalMessagesDropped: 0
  };

  // Connection state for user feedback
  var connectionState = "connecting"; // "connected", "connecting", "disconnected"

  // Message queue for offline operation
  var messageQueue = {
    priority: [],
    normal: [],
    low: []
  };
  var lastMessageId = 0;
  var pendingAcks = new Set();

  // Connection logging
  var connectionEvents = [];
  var maxConnectionEvents = 100;

  // Connection timeout
  var connectionTimeout = null;

  // Ping/Pong health monitoring
  var pingInterval = null;
  var pingTimeout = null;
  var lastPongTime = 0;
  var pingIntervalTime = 30000; // 30 seconds
  var pongTimeoutTime = 5000; // 5 seconds

  // Cross-tab coordination
  var connectionChannel = null;

  // Rate limiting
  var lastMessageTime = 0;
  var minMessageInterval = 0; // 0 = no rate limiting by default

  // ============================================================================
  // UTILITY FUNCTIONS
  // ============================================================================

  function generateId() {
    return 'id-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9);
  }

  function logConnectionEvent(eventType, details) {
    var event = {
      timestamp: new Date().toISOString(),
      type: eventType,
      connectionState: connectionState,
      reconnectAttempts: reconnectAttempts,
      url: window.location.href
    };

    if (details) {
      Object.keys(details).forEach(function(key) {
        event[key] = details[key];
      });
    }

    connectionEvents.push(event);
    if (connectionEvents.length > maxConnectionEvents) {
      connectionEvents.shift();
    }

    // Log to console in development
    if (isDevelopmentEnvironment()) {
      console.log('[WF Connection]', eventType, event);
    }
  }

  function isDevelopmentEnvironment() {
    return window.location.hostname === 'localhost' || 
           window.location.hostname === '127.0.0.1' ||
           window.location.port !== '' && window.location.port !== '80' && window.location.port !== '443';
  }

  function calculateSuccessRate() {
    if (reconnectionHistory.length < 5) return 1.0;
    var recent = reconnectionHistory.slice(-5);
    var successes = recent.filter(function(r) { return r.success; }).length;
    return successes / recent.length;
  }

  function broadcastConnectionState() {
    if (connectionChannel) {
      connectionChannel.postMessage({
        type: 'wf:connection-state',
        state: connectionState,
        reconnectAttempts: reconnectAttempts
      });
    }
  }

  // ============================================================================
  // CONNECTION STATE MANAGEMENT
  // ============================================================================

  function setConnectionState(state) {
    connectionState = state;
    updateConnectionUI();
    broadcastConnectionState();
    logConnectionEvent('state-change', { state: state });
  }

  function updateConnectionUI() {
    var indicator = document.getElementById("wf-connection-status");
    if (indicator) {
      if (connectionState === "disconnected" && reconnectAttempts >= maxReconnectAttempts) {
        // Show reconnect button when permanently disconnected
        var buttonHtml = '<button class="wf-reconnect-btn">Reconnect</button>';
        var queuedCount = messageQueue.priority.length + messageQueue.normal.length + messageQueue.low.length;
        if (queuedCount > 0) {
          buttonHtml = '<button class="wf-reconnect-btn">Reconnect (' + queuedCount + ' queued)</button>';
        }
        indicator.innerHTML = 'disconnected ' + buttonHtml;
        indicator.className = "wf-connection-" + connectionState;
        
        // Set up reconnect button click handler
        var btn = indicator.querySelector('.wf-reconnect-btn');
        if (btn && !btn.hasReconnectHandler) {
          btn.hasReconnectHandler = true;
          btn.addEventListener('click', function(e) {
            e.stopPropagation();
            reconnectAttempts = 0;
            cancelReconnect();
            connect();
          });
        }
      } else {
        indicator.textContent = connectionState;
        indicator.className = "wf-connection-" + connectionState;
      }
    }

    // Dispatch custom event for applications to handle
    var event = new CustomEvent("wf:connection-state", {
      detail: {
        state: connectionState,
        isPermanentlyDisconnected: reconnectAttempts >= maxReconnectAttempts,
        reconnectAttempts: reconnectAttempts,
        maxReconnectAttempts: maxReconnectAttempts,
        queuedMessages: messageQueue.priority.length + messageQueue.normal.length + messageQueue.low.length
      }
    });
    document.dispatchEvent(event);
  }

  // ============================================================================
  // RECONNECTION LOGIC
  // ============================================================================

  function getReconnectDelay() {
    // Exponential backoff with jitter: base * 2^n + random jitter
    var exponentialDelay = reconnectBaseDelay * Math.pow(2, reconnectAttempts);
    var jitter = Math.random() * reconnectBaseDelay;
    var delay = Math.min(exponentialDelay + jitter, reconnectMaxDelay);
    return delay;
  }

  function scheduleReconnect() {
    if (reconnectAttempts >= maxReconnectAttempts) {
      setConnectionState("disconnected");
      
      // Adaptive strategy: adjust delays based on success rate
      var recentSuccessRate = calculateSuccessRate();
      if (recentSuccessRate < 0.5) {
        // Low success rate, increase base delay
        reconnectBaseDelay = Math.min(reconnectBaseDelay * 2, 10000);
      } else if (recentSuccessRate > 0.8 && reconnectBaseDelay > 1000) {
        // Good success rate, decrease base delay
        reconnectBaseDelay = Math.max(Math.floor(reconnectBaseDelay / 2), 1000);
      }
      
      // Record failed reconnection attempt
      reconnectionHistory.push({ success: false, timestamp: Date.now() });
      if (reconnectionHistory.length > 20) reconnectionHistory.shift();
      
      return;
    }

    // Rate limiting: enforce minimum interval
    var now = Date.now();
    var timeSinceLast = now - lastReconnectTime;
    
    if (timeSinceLast < minReconnectInterval) {
      var waitTime = minReconnectInterval - timeSinceLast;
      reconnectTimeoutId = setTimeout(scheduleReconnect, waitTime);
      return;
    }

    lastReconnectTime = now;

    if (reconnectTimeoutId) {
      clearTimeout(reconnectTimeoutId);
    }

    var delay = getReconnectDelay();
    setConnectionState("connecting");

    reconnectTimeoutId = setTimeout(function () {
      reconnectAttempts++;
      connect();
    }, delay);
  }

  function cancelReconnect() {
    if (reconnectTimeoutId) {
      clearTimeout(reconnectTimeoutId);
      reconnectTimeoutId = null;
    }
    if (connectionTimeout) {
      clearTimeout(connectionTimeout);
      connectionTimeout = null;
    }
    reconnectAttempts = 0;
  }

  // ============================================================================
  // CONNECTION MANAGEMENT
  // ============================================================================

  function connect() {
    if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
      return;
    }

    if (isConnecting) {
      return;
    }

    isConnecting = true;
    setConnectionState("connecting");

    var path = document.body.getAttribute("data-wf-ws") || "/ws";
    var scheme = window.location.protocol === "https:" ? "wss:" : "ws:";

    try {
      socket = new WebSocket(scheme + "//" + window.location.host + path);

      // Set connection timeout
      connectionTimeout = setTimeout(function() {
        if (socket && socket.readyState === WebSocket.CONNECTING) {
          logConnectionEvent('connection-timeout');
          socket.close();
          scheduleReconnect();
        }
      }, 10000); // 10 second connection timeout

      socket.addEventListener("open", function () {
        if (connectionTimeout) {
          clearTimeout(connectionTimeout);
          connectionTimeout = null;
        }

        isConnecting = false;
        reconnectAttempts = 0;
        lastReconnectTime = Date.now();
        cancelReconnect();
        
        // Record successful reconnection
        reconnectionHistory.push({ success: true, timestamp: Date.now() });
        if (reconnectionHistory.length > 20) reconnectionHistory.shift();

        connectionStats.successfulConnections++;
        connectionStats.lastConnectionTime = Date.now();
        connectionStats.totalConnections++;
        
        setConnectionState("connected");
        logConnectionEvent('open');
        
        // Send hello message with reconnection metadata
        var helloMessage = {
          type: "hello",
          version: 1,
          reconnecting: reconnectAttempts > 0 || lastMessageId > 0,
          lastMessageId: lastMessageId
        };
        socket.send(JSON.stringify(helloMessage));

        // Start ping/pong health checks
        startPing();

        // Send queued messages in priority order
        flushMessageQueue();

        // Update cross-tab state
        broadcastConnectionState();
      });

      socket.addEventListener("message", function (event) {
        connectionStats.totalMessagesReceived++;
        
        var message = null;
        try {
          message = JSON.parse(event.data);
        } catch (error) {
          logConnectionEvent('malformed-message', { error: error.message, data: event.data });
          return;
        }

        // Handle pong messages for health checks
        if (message.type === "pong") {
          if (pingTimeout) {
            clearTimeout(pingTimeout);
            pingTimeout = null;
          }
          lastPongTime = Date.now();
          return;
        }

        // Handle server-initiated reconnection request
        if (message.type === "server_reconnect") {
          logConnectionEvent('server-reconnect-request');
          reconnect();
          return;
        }

        // Handle acknowledgment messages
        if (message.type === "ack" && message.ackId) {
          pendingAcks.delete(message.ackId);
          // Dispatch ack event for callbacks
          document.dispatchEvent(new CustomEvent('wf:ack', {
            detail: { ackId: message.ackId }
          }));
          return;
        }

        // Handle standard patches
        if (message.type === "patches" && Array.isArray(message.patches)) {
          applyPatches(message.patches);
        }
      });

      socket.addEventListener("close", function (event) {
        if (connectionTimeout) {
          clearTimeout(connectionTimeout);
          connectionTimeout = null;
        }
        
        if (pingInterval) {
          clearInterval(pingInterval);
          pingInterval = null;
        }
        if (pingTimeout) {
          clearTimeout(pingTimeout);
          pingTimeout = null;
        }

        isConnecting = false;
        connectionStats.failedConnections++;
        connectionStats.lastDisconnectionTime = Date.now();
        
        var closeDetails = {
          code: event.code,
          reason: event.reason,
          wasClean: event.wasClean
        };
        logConnectionEvent('close', closeDetails);
        
        setConnectionState("disconnected");
        scheduleReconnect();
      });

      socket.addEventListener("error", function (event) {
        isConnecting = false;
        logConnectionEvent('error', { message: event.message || 'WebSocket error' });
      });

    } catch (error) {
      if (connectionTimeout) {
        clearTimeout(connectionTimeout);
        connectionTimeout = null;
      }
      
      isConnecting = false;
      logConnectionEvent('creation-error', { error: error.message });
      setConnectionState("disconnected");
      scheduleReconnect();
    }
  }

  // ============================================================================
  // PING/PONG HEALTH MONITORING
  // ============================================================================

  function startPing() {
    if (pingInterval) return;

    pingInterval = setInterval(function() {
      if (socket && socket.readyState === WebSocket.OPEN) {
        lastPongTime = Date.now();
        
        try {
          socket.send(JSON.stringify({ type: "ping", version: 1, timestamp: Date.now() }));
        } catch (error) {
          logConnectionEvent('ping-failed', { error: error.message });
          return;
        }

        // Set timeout for pong response
        pingTimeout = setTimeout(function() {
          logConnectionEvent('pong-timeout');
          // No pong received, assume connection dead
          if (socket) {
            socket.close();
          }
        }, pongTimeoutTime);
      }
    }, pingIntervalTime);
  }

  function stopPing() {
    if (pingInterval) {
      clearInterval(pingInterval);
      pingInterval = null;
    }
    if (pingTimeout) {
      clearTimeout(pingTimeout);
      pingTimeout = null;
    }
  }

  // ============================================================================
  // MESSAGE HANDLING
  // ============================================================================

  function send(message, options) {
    options = options || {};
    
    message.version = 1;
    
    // Add message ID if acknowledgment requested
    if (options.requireAck) {
      message.ackId = generateId();
      pendingAcks.add(message.ackId);
    }
    
    // Add priority
    var priority = options.priority || 'normal';
    message.priority = priority;
    
    // Add timestamp for debugging
    message.timestamp = Date.now();

    // Rate limiting
    var now = Date.now();
    if (minMessageInterval > 0 && now - lastMessageTime < minMessageInterval) {
      // Rate limited, queue the message
      queueMessage(message, priority);
      return false;
    }
    lastMessageTime = now;

    if (socket && socket.readyState === WebSocket.OPEN) {
      try {
        socket.send(JSON.stringify(message));
        connectionStats.totalMessagesSent++;
        return true;
      } catch (error) {
        logConnectionEvent('send-error', { error: error.message });
        queueMessage(message, priority);
        return false;
      }
    } else {
      // Queue message for when connection is established
      queueMessage(message, priority);
      return false;
    }
  }

  function queueMessage(message, priority) {
    connectionStats.totalMessagesDropped++;
    logConnectionEvent('message-queued', { priority: priority });
    
    if (priority === 'high') {
      messageQueue.priority.unshift(message); // Add to front
    } else if (priority === 'low') {
      messageQueue.low.push(message);
    } else {
      messageQueue.normal.push(message);
    }
    
    // Update UI if we have queued messages
    updateConnectionUI();
  }

  function flushMessageQueue() {
    // Send by priority: priority first, then normal, then low
    var allMessages = [];
    
    // Send priority messages first
    while (messageQueue.priority.length > 0) {
      allMessages.push(messageQueue.priority.shift());
    }
    
    // Then normal messages
    while (messageQueue.normal.length > 0) {
      allMessages.push(messageQueue.normal.shift());
    }
    
    // Finally low priority messages
    while (messageQueue.low.length > 0) {
      allMessages.push(messageQueue.low.shift());
    }

    // Send all messages with rate limiting
    var sentCount = 0;
    allMessages.forEach(function(message) {
      if (Date.now() - lastMessageTime >= minMessageInterval || minMessageInterval === 0) {
        try {
          socket.send(JSON.stringify(message));
          connectionStats.totalMessagesSent++;
          lastMessageTime = Date.now();
          sentCount++;
          
          // If message required ack, keep track
          if (message.ackId) {
            pendingAcks.add(message.ackId);
          }
        } catch (error) {
          logConnectionEvent('queue-flush-error', { error: error.message });
          // Put message back in queue if send failed
          queueMessage(message, message.priority || 'normal');
        }
      } else {
        // Rate limited, put back in queue
        queueMessage(message, message.priority || 'normal');
      }
    });

    logConnectionEvent('queue-flushed', { sent: sentCount, remaining: messageQueue.priority.length + messageQueue.normal.length + messageQueue.low.length });
  }

  // ============================================================================
  // PATCH APPLICATION
  // ============================================================================

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

  // ============================================================================
  // EVENT HANDLERS
  // ============================================================================

  document.addEventListener("click", function (event) {
    var element = event.target.closest("[data-wf-click]");
    if (element) {
      send({ 
        type: "click", 
        id: element.id, 
        action: element.getAttribute("data-wf-click") 
      }, { priority: 'high' });
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
    send({ 
      type: "submit", 
      id: form.id, 
      action: form.getAttribute("data-wf-submit"), 
      fields: fields 
    }, { priority: 'high' });
  });

  // Network online/offline detection
  window.addEventListener('online', function() {
    logConnectionEvent('browser-online');
    if (connectionState === 'disconnected' || connectionState === 'connecting') {
      reconnectAttempts = 0;
      cancelReconnect();
      connect();
    }
  });

  window.addEventListener('offline', function() {
    logConnectionEvent('browser-offline');
    if (socket) {
      socket.close();
    }
    setConnectionState('disconnected');
    cancelReconnect();
  });

  // Cross-tab coordination
  try {
    connectionChannel = new BroadcastChannel('wf-connection');
    connectionChannel.addEventListener('message', function(event) {
      if (event.data.type === 'wf:connection-state') {
        // Sync connection state from other tabs
        if (event.data.state === 'disconnected') {
          // Another tab reported disconnect, close our socket
          if (socket) {
            socket.close();
          }
        }
      }
    });
  } catch (error) {
    // BroadcastChannel not supported in this browser
    logConnectionEvent('broadcast-channel-unsupported');
  }

  // ============================================================================
  // PUBLIC API
  // ============================================================================

  window.WebFramework = {
    // Connection management
    connect: connect,
    disconnect: function() {
      if (socket) {
        socket.close();
      }
      cancelReconnect();
      setConnectionState("disconnected");
    },
    reconnect: function() {
      reconnectAttempts = 0;
      cancelReconnect();
      connect();
    },
    
    // Message sending with options
    send: send,
    sendPriority: function(message) { return send(message, { priority: 'high' }); },
    sendLowPriority: function(message) { return send(message, { priority: 'low' }); },
    sendWithAck: function(message, callback) { 
      var ackId = generateId();
      
      // Store callback
      if (!window.wfAckCallbacks) window.wfAckCallbacks = {};
      window.wfAckCallbacks[ackId] = callback;
      
      // Listen for ack (one-time listener)
      var ackListener = function(event) {
        if (event.detail.ackId === ackId) {
          if (window.wfAckCallbacks[ackId]) {
            window.wfAckCallbacks[ackId](null);
          }
          delete window.wfAckCallbacks[ackId];
          document.removeEventListener('wf:ack', ackListener);
        }
      };
      document.addEventListener('wf:ack', ackListener);
      
      // Add timeout for ack
      var timeoutId = setTimeout(function() {
        if (window.wfAckCallbacks[ackId]) {
          window.wfAckCallbacks[ackId](new Error('Acknowledgment timeout'));
          delete window.wfAckCallbacks[ackId];
          document.removeEventListener('wf:ack', ackListener);
        }
      }, 30000); // 30 second ack timeout
      
      return send(message, { requireAck: true, ackId: ackId, timeoutId: timeoutId });
    },
    
    // Connection state and info
    getConnectionState: function() { return connectionState; },
    getConnectionStats: function() { 
      return JSON.parse(JSON.stringify(connectionStats));
    },
    getConnectionEvents: function() { 
      return connectionEvents.slice(); // Return copy
    },
    clearConnectionEvents: function() { 
      connectionEvents = []; 
    },
    getQueuedMessageCount: function() {
      return messageQueue.priority.length + messageQueue.normal.length + messageQueue.low.length;
    },
    
    // Configuration
    setMaxReconnectAttempts: function(max) { maxReconnectAttempts = max; },
    setReconnectBaseDelay: function(delay) { reconnectBaseDelay = delay; },
    setReconnectMaxDelay: function(delay) { reconnectMaxDelay = delay; },
    setMinReconnectInterval: function(interval) { minReconnectInterval = interval; },
    setMinMessageInterval: function(interval) { minMessageInterval = interval; },
    setPingInterval: function(interval) { 
      pingIntervalTime = interval; 
      if (socket && socket.readyState === WebSocket.OPEN) {
        stopPing();
        startPing();
      }
    },
    setPongTimeout: function(timeout) { pongTimeoutTime = timeout; },
    
    // Utility
    applyPatches: applyPatches,
    flushMessageQueue: flushMessageQueue,
    
    // Debug
    getInternalState: function() {
      return {
        reconnectAttempts: reconnectAttempts,
        connectionState: connectionState,
        isConnecting: isConnecting,
        socketReadyState: socket ? socket.readyState : null,
        messageQueueSize: messageQueue.priority.length + messageQueue.normal.length + messageQueue.low.length,
        pendingAcksCount: pendingAcks.size
      };
    }
  };

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  // Start initial connection
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", connect);
  } else {
    connect();
  }

  // Log initial state
  logConnectionEvent('init', { 
    userAgent: navigator.userAgent,
    online: navigator.onLine
  });

  // Set initial connection state
  if (!navigator.onLine) {
    setConnectionState("disconnected");
  }

}());
