// Messaging
var messageTypes = {
    initialize: 1,
    startRecord: 2,
    startReplay: 3,
    recordFrame: 4,
    endRecord: 5,
    replayFrame: 6
};

var messageHandlers = [];

// Recording
var recording = false;
var interactions = "";
var replayKey = "fbg_replay";

messageHandlers[messageTypes.initialize] = function () {
    return [
        1 // 1 for "communication enabled"
    ];
}

messageHandlers[messageTypes.startRecord] = function (bytes) {
    recording = true;
    interactions = "";
    for (var i = 0; i < bytes.length; i++) {
        interactions += String.fromCharCode(bytes[i]);
    }
};

messageHandlers[messageTypes.recordFrame] = function (bytes) {
    interactions += String.fromCharCode(bytes[0]);
};

messageHandlers[messageTypes.endRecord] = function (bytes) {
    // Read high score
    if (bytes.length === 4) {
        var score = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
    
        // TODO: Upload seed, replay, score; retrieve a graph or high score list or something
        var str = LZString.compressToBase64(interactions);
        localStorage[replayKey] = str;
    }
};

// Playback
var replaying = false;
var replay;
var replayIndex = 0;
messageHandlers[messageTypes.startReplay] = function (bytes) {
    replaying = true;
    replayIndex = 16;
    replay = LZString.decompressFromBase64(localStorage[replayKey]);

    var bytes = [ ];
    for (var i = 0; i < 16; i++) {
        bytes.push(replay.charCodeAt(i));
    }
    return bytes;
};

messageHandlers[messageTypes.replayFrame] = function (bytes) {
    if (replayIndex < replay.length) {
        return [ replay.charCodeAt(replayIndex++) ];
    }
};

comm.subscribe(function (message) {
    if (message.length > 0) {
        var type = message[0];
        var response = messageHandlers[type](message.slice(1)) || [];
        var bytes = [ type ];
        for (var i = 0; i < response.length; i++) {
            bytes.push(response[i]);
        }
        return bytes;
    }
});
