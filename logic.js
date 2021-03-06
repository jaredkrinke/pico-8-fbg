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
    var serviceRoot = "https://fbg-db.netlify.app/.netlify/functions";
    // var serviceRoot = "http://localhost:8888/.netlify/functions"; // Local test server
    var serviceAddScoreEndpoint = serviceRoot + "/addscore";

    function serviceGetTopScoresEndpoint(mode) {
        return serviceRoot + "/topscores?mode=" + encodeURIComponent(mode);
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

    // Shared
    var recording = false;
    var interactions = "";
    var seedString = "";
    var mode = 0;
    var replayKey = "fbg_replay";
    var letters = "abcdefghijklmnopqrstuvwxyz";
    var cachedScores = [];

    // Loading scores
    function serializeInitials(buffer, initials) {
        for (var i = 0; i < initials.length; i++) {
            buffer.push(letters.indexOf(initials[i]) + 1)
        }
    }

    function startLoadingScores(mode) {
        cachedScores[mode] = null;
        $.ajax(serviceGetTopScoresEndpoint(mode), {
            method: "get",
            dataType: "json"
        })
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

    messageHandlers[messageTypes.loadScores] = function (request) {
        var mode = request[0];
        if (cachedScores[mode] === undefined) {
            startLoadingScores(mode);
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

    // Initialization
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

    // Recording
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
        
            // Upload mode, seed, host name, score, replay
            var str = LZString.compressToBase64(interactions);
            // TODO: Re-enable replays, if desired
            // localStorage[replayKey] = str;

            // Reload high scores for this mode, in case anything changed
            // TODO: Smarter logic (e.g. only loading if the new score might make it)
            cachedScores[mode] = null;

            (function (mode) {
                $.ajax(serviceAddScoreEndpoint, {
                    method: "post",
                    data: JSON.stringify({
                        mode: mode,
                        seed: seedString,
                        host: getHostName(),
                        initials: initials,
                        score: score,
                        replay: str
                    }),
                    contentType: "text/plain", // Use "text/plain" to avoid preflight OPTIONS request
                    dataType: "json"
                })
                    .done(function (data) {
                        console.log(data);
                        startLoadingScores(mode);
                    })
                    .fail(function(data) {
                        console.log(data);
                        // Ignore
                    });
            })(mode);
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
})();
