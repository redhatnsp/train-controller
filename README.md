# Demo Stop The Crazy Train - Lego Train Controller

![lego](https://www.lego.com/cdn/cs/set/assets/blt95604d8cc65e26c4/CITYtrain_Hero-XL-Desktop.png?fit=crop&format=webply&quality=80&width=1600&height=1000&dpr=1)

## Description

This demo is a part of global demo "Stop The Crazy train" :
“ The train is running mad at full speed and has no driver ! Your mission, should you choose to accept it, is to train and deploy an AI model at the edge to stop the train before it crashes. This message will self-destruct in five seconds. Four. three. Two. one.  tam tam tada tum tum tada tum tum tada tum tum tada tiduduuuuummmm tiduduuuuuuuuummm ”

## Objectives

Showcase a nodejs application that control a [Lego Train Ref : 60337](https://www.lego.com/en-fr/themes/city/train) using Bluetooth, all commands are read from mqtt broker.

The controller can :

- discover the hub
- start and stop the train
- increase/decrase speed

### Prerequisites

You will need:

- Podman
- Nodejs v20.7.0
- MQTT broker (mosquitto docker image)
- MQTT cli (mosquitto)

### Local installation

On linux

```sh
sudo dnf install -y podman
sudo mkdir -p /tmp/mosquitto/{config,data,log}
sudo tee /tmp/mosquitto/config/mosquitto.conf <<EOF
persistence true
persistence_location /mosquitto/data/
listener 1883 0.0.0.0
protocol mqtt
allow_anonymous true
log_dest file /mosquitto/log/mosquitto.log
EOF
sudo dnf install -y mosquitto
```

On macos

Keep the mosquitto directory under `$HOME`. Podman on macOS runs inside a VM that only
shares `/Users`, `/private` and `/var/folders` with the host, so a bind mount from `/tmp`
fails with `statfs /tmp/mosquitto/config: no such file or directory`.

```sh
mkdir -p "$HOME"/mosquitto/{config,data,log}
tee "$HOME/mosquitto/config/mosquitto.conf" <<EOF
persistence true
persistence_location /mosquitto/data/
listener 1883 0.0.0.0
protocol mqtt
allow_anonymous true
log_dest stdout
EOF
chmod -R a+rwX "$HOME"/mosquitto/{data,log}
brew install mosquitto
```

`log_dest stdout` keeps the broker logs visible via `podman logs mosquitto` and avoids
write-permission errors, since the container runs as uid 1883 against a virtiofs mount.

Install package dependencies nodejs.

```sh
npm install
```

If this fails while building `@abandonware/noble` with `ModuleNotFoundError: No module
named 'distutils'`, the bundled node-gyp (9.4.1) is being run against Python 3.12 or
newer, which dropped `distutils`. Point node-gyp at a Python 3.11 venv instead:

```sh
python3.11 -m venv .venv-nodegyp
export npm_config_python="$PWD/.venv-nodegyp/bin/python"
npm install
```

Node v26 works despite the v20.7.0 listed above, once the Python issue is resolved.

### Test

Run the mqtt broker on linux.

```sh
sudo podman run -d --rm --name mosquitto -p 1883:1883 -p 9001:9001 -v /tmp/mosquitto/config:/mosquitto/config:z -v /tmp/mosquitto/data:/mosquitto/data:z -v /tmp/mosquitto/log:/mosquitto/log:z docker.io/library/eclipse-mosquitto:2.0.18
```

Run the mqtt broker on macos.

```sh
podman run -d --rm --name mosquitto -p 1883:1883 -p 9001:9001 -v "$HOME/mosquitto/config:/mosquitto/config" -v "$HOME/mosquitto/data:/mosquitto/data" -v "$HOME/mosquitto/log:/mosquitto/log" docker.io/library/eclipse-mosquitto:2.0.18
```

Confirm the config was actually mounted:

```sh
podman logs mosquitto
```

You should see `Config loaded from /mosquitto/config/mosquitto.conf.`. If that line is
missing, the mount did not reach the container and mosquitto 2.0 has fallen back to its
defaults (localhost-only listener, `allow_anonymous false`), which refuses every
connection from the host.

On linux, you have to configure DBUS:

```sh
cat > /etc/dbus-1/system.d/node-ble.conf <<EOF
<busconfig>
  <policy user="$(id -un)">
   <allow own="org.bluez"/>
    <allow send_destination="org.bluez"/>
    <allow send_interface="org.bluez.GattCharacteristic1"/>
    <allow send_interface="org.bluez.GattDescriptor1"/>
    <allow send_interface="org.freedesktop.DBus.ObjectManager"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
  </policy>
</busconfig>
EOF
```

Run the controller.

```sh
export NOBLE_USE_BLUEZ_WITH_DBUS=true
export DEBUG="bluez-dbus-bindings,poweredup,technicmediumhub,basehub"
node ./index.js
```

You should see something like this.

```
Connecting to MQTT broker mqtt://localhost:1883...
Scanning for Lego PoweredUp Hubs...
Connected to MQTT broker mqtt://localhost:1883!
Subscribed to topic train-command!
Connected to Lego Hub!
All hardware pieces have been discovered!
Lego City Train #60337 reached max speed!
```

Send all MQTT commands sequentially.

```sh
for cmd in `seq 0 1`; do mosquitto_pub -h localhost -p 1883 -t train-command -m "$cmd"; sleep 10; done
```

On the train-controller logs, you should see something like this.

```
Received message on MQTT topic train-command: 0
Handling SpeedLimit_30...
Processed command 0!
Received message on MQTT topic train-command: 1
Handling DangerAhead...
Processed command 1!
```

## Configuration

Everything is set through environment variables; there is no config file.

| Variable | Default | Purpose |
|---|---|---|
| `MQTT_BROKER_URL` | `mqtt://localhost:1883` | Broker to subscribe to |
| `MQTT_TOPIC` | `train-command` | Topic commands arrive on |
| `LEGO_BACKEND` | `bluetooth` | Which backend to load from `src/`. Set to `mock` to run with no hardware |
| `LEGO_MOTOR_FULL_POWER` | `100` | Motor power for normal running |
| `LEGO_MOTOR_LOW_POWER` | `70` | Motor power after a SpeedLimit sign, and the floor of the ramp-up |
| `LEGO_SLEEP_TIME` | `1000` | Milliseconds to pause mid-action, after the LED flashes |
| `LEGO_RAMPUP_TIME` | `1000` | Milliseconds to ramp from low to full power |
| `DEBUG` | *(unset)* | `debug` namespaces to print: `main` for MQTT and command handling, `lego-gear-bluetooth` or `lego-gear-mock` for the backend |

Most of the interesting logging is on the `main` namespace, so `DEBUG=main` is usually
what you want; without it the MQTT messages are invisible.

## Available commands

The payload on `train-command` is not JSON — it is the command id as a bare string.

| Id | Action | Behaviour |
|---|---|---|
| `0` | SpeedLimit_30 | Drop to `LEGO_MOTOR_LOW_POWER`, flash the LED, pause, return to full power |
| `1` | DangerAhead | Brake, flash the LED, pause, ramp back up |
| `2` | Start Train | Flash the LED, pause, ramp up |
| `3` | Stop Train | Brake, flash the LED, and stay stopped |
| `-1` | *(no detections)* | Not in the action map; logged as unknown and ignored |

Commands `0` and `1` come from the AI pipeline — they are the model's class ids, passed
through `train-ceq-app` unchanged. There is no translation layer, so renumbering the
model's classes changes what the train does.

Commands `2` and `3` are not produced by the AI path at all. They come from the operator
buttons on the monitoring app, which reach `train-capture-image-app`, which publishes
them to this topic directly.

## Enabling the Mock

If you do not have a proper Lego Hub, you can mock it.

```sh
export LEGO_BACKEND=mock
export DEBUG="main,lego-gear-mock"
node ./index.js
```

Include the `main` namespace as well as the backend one, otherwise the MQTT subscription
and the received commands are not logged and it looks like nothing is happening.

With the mock backend no Bluetooth stack is loaded at all — `index.js` only requires
`./src/${LEGO_BACKEND}`, so `src/bluetooth.js` and its native dependencies are never
touched. This is the quickest way to exercise the command path on a machine with no LEGO
hardware.

## Known issues

- **The process exits when the MQTT connection drops.** The broker `close` event is wired
  straight to `cleanupAndExit()`, which calls `process.exit(0)`. A brief broker blip
  therefore terminates the controller; under MicroShift that shows up as a pod restart,
  after which the hub has to be paired again within the short window described below.
  This is the leading suspect for the "train runs for about 30 seconds and then stops"
  symptom in the demo runbook — worth checking the pod restart count before changing
  anything else.
- **Commands arriving during an action are dropped, not queued.** An `actionInProgress`
  flag gates the handler, and an action takes about two seconds for `0` and `3` (four
  250 ms LED flashes plus `LEGO_SLEEP_TIME`) and about three for `1` and `2`, which also
  ramp back up over `LEGO_RAMPUP_TIME`. Anything received in that window is logged as
  `Ignoring command N since the last one is still ongoing` and discarded. At the capture
  app's default 30 ms frame interval the large majority of detections never reach the
  motor. This is deliberate — it stops the train stuttering — but it is worth knowing
  before trying to diagnose "missed" signs.
- **The train starts on its own.** When the hub reports `ready`, the controller
  immediately ramps the motor to full power, before any MQTT message arrives. That is
  why pressing the button on the engine is enough to set the train moving.
- **Pairing is timing sensitive.** In the field the hub frequently fails to connect
  unless the Bluetooth button is pressed within about 30 seconds of the controller
  starting. The documented workaround is to restart the deployment and press the button
  immediately afterwards.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file
for details.
