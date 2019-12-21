var initializeSocket = function ({ onMessage, onOpen, onClose, onError }) {
  var socket = new WebSocket("ws://localhost:4567/cable");

  socket.onopen = function (_event) {
    console.log("WebSocket connected");
    if (onOpen) {
      onOpen(sendData);
    }
  };

  socket.onclose = function (event) {
    if (event.wasClean) {
      console.log("WebSocket connection closed");
    } else {
      console.log("WebSocket connection closed dirty"); // for example server process was killed
    }
    console.log('WebSocket code: ' + event.code + ' reason: ' + event.reason);
    if (onClose) {
      onClose(event.wasClean, event.code, event.reason);
    }
  };

  socket.onmessage = function (event) {
    console.log("WebSocket data received " + event.data);
    if (onMessage) {
      onMessage(JSON.parse(event.data));
    }
  };

  socket.onerror = function (error) {
    console.log("WebSocket error " + error.message);
    if (onError) {
      onError(error);
    }
  };

  var sendData = function (data) {
    socket.send(JSON.stringify(data));
  }

  return { socket, sendData };
};

window.MainApp = { handler: null };

var chatTextArea = document.querySelector('.js-response');
var chatInput = document.querySelector('.js-input');
var sendBtn = document.querySelector('.js-send');
var loginBtn = document.querySelector('.js-login');
var loginInput = document.querySelector('.js-login-input');
var logoutBtn = document.querySelector('.js-logout');
var reloadBtn = document.querySelector('.js-reload');

var addToChat = function (who, message) {
  var oldVal = ""
  if (chatTextArea.value.length > 0) {
    oldVal += chatTextArea.value + "\n"
  }
  chatTextArea.value = oldVal + who + ": " + message;
}

var sendXhr = function ({ method, url, payload, onResponse }) {
  var newXHR = new XMLHttpRequest();
  if (onResponse) {
    newXHR.addEventListener('load', function () {
      onResponse(this.response);
    });
  }
  newXHR.open(method, url);
  newXHR.send(payload);
}

var onWebSocketMessage = function (data) {
  if (!data.message) {
    console.log('empty message skipped on receive', data);
    return
  }
  console.log('msg received', data);
  addToChat(data.who || 'Unknown', data.message);
}

var onWebSocketOpen = function (_send) {
  chatInput.value = "";
  chatTextArea.value = "";
}

MainApp.handler = initializeSocket({
  onMessage: onWebSocketMessage,
  onOpen: onWebSocketOpen
});

sendBtn.addEventListener('click', function (_event) {
  var message = chatInput.value;
  if (!message) {
    console.log('empty msg skipped on send', message);
    return
  }
  console.log('send message', message);
  MainApp.handler.sendData({ message });
  addToChat('You', message);
  chatInput.value = "";
});

loginBtn.addEventListener('click', function (event) {
  event.preventDefault();
  var login = loginInput.value;
  console.log('login as', login);
  sendXhr({
    method: 'POST',
    url: '/login?' + login,
    payload: JSON.stringify({ login }),
    onResponse: function (response) {
      console.log('login response', response);
    }
  });
});

logoutBtn.addEventListener('click', function (event) {
  event.preventDefault();
  console.log('logout');
  sendXhr({
    method: 'DELETE',
    url: '/logout',
    onResponse: function (response) {
      console.log('logout response', response);
    }
  })
});

reloadBtn.addEventListener('click', function (event) {
  event.preventDefault();
  console.log('reload websocket');
  MainApp.handler.socket.close(1000, 'reload');
  MainApp.handler = initializeSocket({
    onMessage: onWebSocketMessage,
    onOpen: onWebSocketOpen
  });
});
