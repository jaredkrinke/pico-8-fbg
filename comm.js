var comm;
(function () {
    // PICO-8 to HTML host communication (synchronous)
    
    // GPIO array with hook/callback support
    var length = 128;
    function HookedArray() {
        Array.call(this, length);
        this.data = Array(length);
        this.callbacks = [];
    }

    HookedArray.prototype = Object.create(Array.prototype, {
        length: {
            value: length,
            writable: false
        }
    })

    HookedArray.prototype.subscribe = function (callback) {
        this.callbacks.push(callback);
    }

    HookedArray.prototype.setSilent = function (index, value) {
        this.data[index] = value;
    }

    for (var i = 0; i < length; i++) {
        (function (i) {
            Object.defineProperty(HookedArray.prototype, i, {
                get: function () {
                    return this.data[i];
                },

                set: function (value) {
                    this.data[i] = value;
                    for (var j = 0; j < this.callbacks.length; j++) {
                        this.callbacks[j](i);
                    }
                }
            });
        })(i);
    }

    window.pico8_gpio = new HookedArray();

    // Callback/interface
    var gpio = window.pico8_gpio;
    function Comm() {
        this.callbacks = [];
    }

    Comm.prototype.subscribe = function (callback) {
        this.callbacks.push(callback);
    };

    comm = new Comm();

	// Writing
	var gpioIndex = {
		size: 0,
		base: 1
	};

	function sendMessage(bytes) {
        bytes = bytes || [];
		gpio.setSilent(gpioIndex.size, bytes.length);
		var writeIndex = gpioIndex.base;
		for (var i = 0; i < bytes.length; i++) {
			gpio.setSilent(writeIndex++, bytes[i]);
		}
	}

	// Reading
	var readStates = {
		readSize: 0,
		readBody: 1
	};

	var readState;
	var readIndex;
	var remainingBytes;
	var message;

	function stateReset() {
		readState = readStates.readSize;
		readIndex = gpioIndex.size;
		remainingBytes = 0;
		message = [];
	}

	stateReset();

	function stateCheckForEnd() {
		if (remainingBytes <= 0) {
            for (var i = 0; i < comm.callbacks.length; i++) {
                sendMessage(comm.callbacks[i](message));
            }

			stateReset();
		}
	}

	gpio.subscribe(function (index) {
		switch (readState) {
			case readStates.readSize:
			if (readIndex === index) {
				remainingBytes = gpio[readIndex++];
				readState = readStates.readBody;
				stateCheckForEnd();
			}
			break;

			case readStates.readBody:
			if (readIndex === index) {
				message.push(gpio[readIndex++]);
				remainingBytes--;
				stateCheckForEnd();
			}
			break;
		}
	});
})();
