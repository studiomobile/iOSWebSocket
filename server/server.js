var util = require('util')
  , url = require('url')
  , http = require('http')
  , WebSocketServer = require('ws').Server
  , server = new WebSocketServer({port: 9000})
  , urlRegex = /http:\/\/([\da-z-]+\.)+([a-z]{2,6})/i

console.log("Starting server or port 9000")

server.on('connection', function(socket) {
  console.log('Client connected');
  socket.alive = true;

  socket.on('message', function(msg) {
    console.log('>' + msg)
    var idx = msg.search(urlRegex)
      , u = idx >= 0 && url.parse(msg.substring(idx));
    if (u) {
      socket.send("Fetching " + u.href);
      http.get(u, function(res) {
        if (!socket.alive) {
          res.destroy();
          return;
        }
        res.setEncoding('utf8');
        res.on('data', function(data) {
          socket.send(data);
        });
        socket.send(util.inspect(res.headers));
        socket.on('close', function() {
          res.destroy();
        });
      });
    } else if (msg.match(/ping/)) {
      socket.send('Ping from server');
      socket.ping(new Date().toISOString());
    } else {
      socket.send(msg);
    }
  });

  socket.on('pong', function(data) {
    var now = new Date()
      , num = Date.parse(data)
      , date = num && new Date(num);
    if (date) {
      var diff = now.getTime() - date.getTime();
      console.log('Ping/pong (in millis): ' + diff);
      socket.send('Ping/pong on server (in millis): ' + diff);
    } else {
      console.log('Bad Pong: ' + data);
    }
  });

  socket.on('close', function() {
    socket.alive = false;
    console.log('Client disconnected');
  });

  socket.on('error', function(code, description) {
    console.log("Error " + code + " " + description)
  });
});
