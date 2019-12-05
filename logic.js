(function () {
    // Messaging
    var messageTypes = {
        initialize: 1,
        startRecord: 2,
        startReplay: 3,
        recordFrame: 4,
        endRecord: 5,
        replayFrame: 6,
        loadScores: 7,
        checkScores: 8
    };

    var messageHandlers = [];

    // Service
    // var serviceRoot = "https://fbg.schemescape.com";
    var serviceRoot = "http://localhost:17476"; // Local test server

    function serviceGetModeRoot(mode) {
        return serviceRoot + "/scores/" + encodeURIComponent(mode);
    }

    // Local storage
    var hostNameKey = "fbg_host";
    var hostNameLength = 15;
    function generateHostName() {
        var characters = "abcdefghijklmnopqrstuvwxyz";
        var id = "";
        for (var i = 0; i < hostNameLength; i++) {
            // TODO: Use crypto.getRandomValues?
            id += characters[Math.floor(Math.random() * characters.length)];
        }
        return id;
    }

    function getHostName() {
        var hostName = localStorage[hostNameKey];
        if (hostName && hostName.length == hostNameLength) {
            return hostName;
        } else {
            hostName = generateHostName();
            localStorage[hostNameKey] = hostName;
            return hostName;
        }
    }

    // Recording
    var recording = false;
    var interactions = "";
    var seedString = "";
    var mode = 0;
    var replayKey = "fbg_replay";
    var letters = "abcdefghijklmnopqrstuvwxyz";

    messageHandlers[messageTypes.initialize] = function () {
        return [
            1, // 1 for "communication enabled"
            (typeof(localStorage[replayKey]) == "string") ? 1 : 0 // replay available
        ];
    }

    function formatHexByte(byte) {
        var str;
        if (byte < 16) {
            str = "0";
        } else {
            str = "";
        }

        str += byte.toString(16).toLowerCase();
        return str;
    }

    function serializeUInt32(buffer, score) {
        buffer.push(score & 0xff);
        buffer.push((score >>> 8) & 0xff);
        buffer.push((score >>> 16) & 0xff);
        buffer.push((score >>> 24) & 0xff);
    }

    messageHandlers[messageTypes.startRecord] = function (request) {
        // TODO: Consider creating the seed service-side
        var seeds = crypto.getRandomValues(new Uint32Array(4));
        var response = [];
        for (var i = 0; i < seeds.length; i++) {
            serializeUInt32(response, seeds[i]);
        }

        seedString = "";
        for (var i = 0; i < response.length; i++) {
            seedString += formatHexByte(response[i]);
        }

        recording = true;
        interactions = "";
        mode = request[0];

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
        if (bytes.length === 7) {
            var score = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
            var initials = "";
            for (var i = 0; i < 3; i++) {
                initials += letters[bytes[4 + i] - 1];
            }
        
            // Upload mode, seed, host name, score, replay; retrieve a graph or high score list or something
            var str = LZString.compressToBase64(interactions);
            localStorage[replayKey] = str;

            $.ajax(serviceGetModeRoot(mode) + "/" + seedString, {
                method: "put",
                data: {
                    hostName: getHostName(),
                    initials: initials,
                    score: score,
                    replay: str
                },
                dataType: "json"
            })
                .done(function () {
                    // TODO
                })
                .fail(function() {
                    // TODO
                });
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

    // Loading scores
    var cachedScores = [];
    function serializeInitials(buffer, initials) {
        for (var i = 0; i < initials.length; i++) {
            buffer.push(letters.indexOf(initials[i]) + 1)
        }
    }

    messageHandlers[messageTypes.loadScores] = function (request) {
        var mode = request[0];
        // TODO: Consider not caching these indefinitely
        if (cachedScores[mode] === undefined) {
            $.ajax(serviceGetModeRoot(mode), { method: "get" })
                .done(function (scores) {
                    var bytes = [];
                    for (var i = 0; i < scores.length; i++) {
                        var entry = scores[i];
                        serializeInitials(bytes, entry.initials);
                        serializeUInt32(bytes, entry.score);
                    }
                    cachedScores[mode] = bytes;
                })
                .fail(function() {
                    cachedScores[mode] = -1;
                });
        }
    }

    messageHandlers[messageTypes.checkScores] = function (request) {
        var mode = request[0];
        var response = [];
        if (cachedScores[mode] === -1) {
            response.push(0xff); // Error
        } else if (cachedScores[mode]) {
            response = cachedScores[mode];
        }
        return response;
    }

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
})();
