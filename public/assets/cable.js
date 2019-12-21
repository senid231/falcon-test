var initializeSocket = function () {
  var socket = new WebSocket("ws://localhost:4567/cable");


  socket.onopen = function (_event) {
    console.log("WebSocket connected");
    socket.send(JSON.stringify({ greeting: 'hello server' }));
  };

  socket.onclose = function (event) {
    if (event.wasClean) {
      console.log("WebSocket connection closed");
    } else {
      console.log("WebSocket connection closed dirty"); // for example server process was killed
    }
    console.log('WebSocket code: ' + event.code + ' reason: ' + event.reason);
  };

  socket.onmessage = function (event) {
    console.log("WebSocket data received " + event.data);
  };

  socket.onerror = function (error) {
    console.log("WebSocket error " + error.message);
  };

  return socket
}

window.MainApp = { socket: null };
MainApp.socket = initializeSocket();
