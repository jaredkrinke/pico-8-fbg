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
        1, // 1 for "communication enabled"
        (typeof(localStorage[replayKey]) == "string") ? 1 : 0 // replay available
    ];
}

messageHandlers[messageTypes.startRecord] = function (request) {
    // TODO: Consider creating the seed service-side
    var seeds = crypto.getRandomValues(new Uint32Array(4));
    var response = [];
    for (var i = 0; i < seeds.length; i++) {
        var seed = seeds[i];
        response.push(seed & 0xff);
        response.push((seed >>> 8) & 0xff);
        response.push((seed >>> 16) & 0xff);
        response.push((seed >>> 24) & 0xff);
    }

    recording = true;
    interactions = "";

    // Log seed
    for (var i = 0; i < response.length; i++) {
        interactions += String.fromCharCode(response[i]);
    }

    // Log mode and level
    for (var i = 0; i < request.length; i++) {
        interactions += String.fromCharCode(request[i]);
    }
    return response;
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
messageHandlers[messageTypes.startReplay] = function () {
    replaying = true;
    replayIndex = 0;
    replay = LZString.decompressFromBase64(localStorage[replayKey]);

    var bytes = [];
    // Send seed, mode, level
    for (replayIndex = 0; replayIndex < 18; replayIndex++) {
        bytes.push(replay.charCodeAt(replayIndex));
    }
    return bytes;
};

messageHandlers[messageTypes.replayFrame] = function () {
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
