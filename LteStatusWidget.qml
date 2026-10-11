import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Look and behaviour modelled on the built-in VPN widget (Vpn.qml,
// VpnDetailContent.qml): primary-coloured icon when connected, translucent
// while busy, right click toggles, pill buttons in the popout.
PluginComponent {
    id: root

    property string scriptPath: Qt.resolvedUrl("get-lte-status").toString().replace("file://", "")

    // off | on | connected
    property string modemState: "off"
    property string ipAddr: ""
    property string operatorName: ""
    property int uptimeSec: -1
    property real rxBytes: 0
    property real txBytes: 0
    // xmm7360.service state: active | activating | deactivating | inactive | failed
    property string unitState: "inactive"
    property string actionError: ""

    readonly property bool connected: modemState === "connected"
    readonly property bool failed: unitState === "failed"
    readonly property bool busy: unitState === "activating" || unitState === "deactivating" || controlProcess.running

    readonly property string stateIcon: connected ? "signal_cellular_alt"
                                      : failed ? "signal_cellular_connected_no_internet_0_bar"
                                      : modemState === "on" ? "signal_cellular_null"
                                      : "signal_cellular_off"
    readonly property color stateColor: connected ? Theme.primary
                                      : failed ? Theme.error
                                      : Theme.widgetIconColor
    readonly property string stateLabel: unitState === "activating" ? "Connecting…"
                                       : unitState === "deactivating" ? "Disconnecting…"
                                       : connected ? "Connected"
                                       : failed ? "Connection failed"
                                       : modemState === "on" ? "Modem on"
                                       : "Off"

    function formatBytes(b) {
        if (b < 1024)
            return b + " B";
        if (b < 1024 * 1024)
            return (b / 1024).toFixed(1) + " KB";
        if (b < 1024 * 1024 * 1024)
            return (b / 1024 / 1024).toFixed(1) + " MB";
        return (b / 1024 / 1024 / 1024).toFixed(2) + " GB";
    }

    function parseLine(line) {
        var i = line.indexOf("=");
        if (i < 0)
            return;
        var key = line.substring(0, i);
        var val = line.substring(i + 1);
        if (key === "state")
            modemState = val;
        else if (key === "operator")
            operatorName = val;
        else if (key === "uptime")
            uptimeSec = val === "" ? -1 : Number(val);
        else if (key === "unit")
            unitState = val || "inactive";
        else if (key === "ip")
            ipAddr = val;
        else if (key === "rx")
            rxBytes = Number(val) || 0;
        else if (key === "tx")
            txBytes = Number(val) || 0;
    }

    // systemctl start/stop -- no password thanks to polkit rule 49-xmm7360.rules
    function control(verb) {
        if (controlProcess.running)
            return;
        actionError = "";
        controlProcess.command = ["systemctl", verb, "xmm7360.service"];
        controlProcess.running = true;
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function toggle() {
        if (busy)
            return;
        if (unitState === "active" || modemState !== "off")
            control("stop");
        else
            control(failed ? "restart" : "start");
    }

    Process {
        id: statusProcess
        command: ["timeout", "10", "bash", root.scriptPath]
        running: false

        stdout: SplitParser {
            onRead: data => root.parseLine(data.trim())
        }
    }

    Process {
        id: controlProcess
        running: false

        stderr: SplitParser {
            onRead: data => root.actionError = data.trim()
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.actionError)
                root.actionError = "Failed (details: /var/log/xmm7360.log)";
            if (!statusProcess.running)
                statusProcess.running = true;
        }
    }

    Timer {
        interval: root.busy ? 1000 : 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!statusProcess.running)
                statusProcess.running = true;
        }
    }

    pillRightClickAction: () => root.toggle()


    horizontalBarPill: Component {
        Item {
            implicitWidth: hIcon.width
            implicitHeight: root.iconSize

            DankIcon {
                id: hIcon
                name: root.stateIcon
                size: root.iconSize
                color: root.stateColor
                opacity: root.busy ? 0.5 : 1.0
                anchors.centerIn: parent

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: root.iconSize
            implicitHeight: vIcon.height

            DankIcon {
                id: vIcon
                name: root.stateIcon
                size: root.iconSize
                color: root.stateColor
                opacity: root.busy ? 0.5 : 1.0
                anchors.centerIn: parent

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }


    function formatDuration(s) {
        if (s < 60)
            return s + " s";
        var m = Math.floor(s / 60);
        if (m < 60)
            return m + " min";
        return Math.floor(m / 60) + " h " + (m % 60) + " min";
    }

    // Tile like "Health"/"Capacity" in BatteryPopout.qml
    component StatTile: StyledRect {
        id: tile
        property string label: ""
        property string value: ""

        height: 64
        radius: Theme.cornerRadius
        color: Theme.nestedSurface
        border.width: 0

        Column {
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            StyledText {
                text: tile.label
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: tile.value
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // Full-width button, height and colours like DankButtonGroup
    // (selected segment = buttonBg, others = surfaceVariant).
    component ActionButton: Rectangle {
        id: action
        property string iconName: ""
        property string label: ""
        property bool accent: false
        signal clicked

        height: 40
        radius: Theme.cornerRadius
        color: accent ? Theme.buttonBg : Theme.withAlpha(Theme.surfaceVariant, Theme.popupTransparency)
        opacity: root.busy ? 0.5 : 1.0

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: actionArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.08) : "transparent"
        }

        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingS

            DankIcon {
                name: action.iconName
                size: Theme.iconSize - 4
                color: action.accent ? Theme.buttonText : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: action.label
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: action.accent ? Theme.buttonText : Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: actionArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.busy ? Qt.BusyCursor : Qt.PointingHandCursor
            enabled: !root.busy
            onClicked: action.clicked()
        }
    }

    // Layout like BatteryPopout.qml: no separate header or wrapper card,
    // icon + large state + close in one row, tiles directly on the background.
    popoutWidth: 400

    popoutContent: Component {
        Item {
            id: popout
            property var closePopout: null

            width: parent ? parent.width : 400
            // PluginPopout adds spacingS around, add the rest up to spacingL here
            implicitHeight: body.implicitHeight + Theme.spacingS * 2

            Column {
                id: body
                width: parent.width - Theme.spacingS * 2
                x: Theme.spacingS
                y: Theme.spacingS
                spacing: Theme.spacingL

                Row {
                    width: parent.width
                    height: 48
                    spacing: Theme.spacingM

                    DankIcon {
                        name: root.stateIcon
                        size: Theme.iconSizeLarge
                        color: root.stateColor
                        opacity: root.busy ? 0.5 : 1.0
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        width: parent.width - Theme.iconSizeLarge - 32 - Theme.spacingM * 2
                        spacing: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter

                        Row {
                            spacing: Theme.spacingS

                            StyledText {
                                text: root.connected && root.operatorName ? root.operatorName : root.stateLabel
                                font.pixelSize: Theme.fontSizeXLarge
                                font.weight: Font.Bold
                                color: root.connected ? Theme.primary : root.failed ? Theme.error : Theme.surfaceText
                            }

                            StyledText {
                                visible: root.connected
                                text: "LTE"
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Medium
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                id: uptimeText
                                visible: root.connected && root.uptimeSec >= 0
                                text: root.formatDuration(root.uptimeSec)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.primary
                            }

                            StyledText {
                                text: root.connected ? root.ipAddr
                                    : root.busy ? "Please wait…"
                                    : root.failed ? "Check /var/log/xmm7360.log"
                                    : root.modemState === "on" ? "Not connected to the network"
                                    : "Radio off"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceTextMedium
                                elide: Text.ElideRight
                                width: parent.width - (uptimeText.visible ? uptimeText.implicitWidth + parent.spacing : 0)
                            }
                        }
                    }

                    Rectangle {
                        width: 32
                        height: 32
                        radius: 16
                        color: closeArea.containsMouse ? Theme.errorHover : Theme.withAlpha(Theme.errorHover, 0)
                        anchors.top: parent.top

                        DankIcon {
                            anchors.centerIn: parent
                            name: "close"
                            size: Theme.iconSize - 4
                            color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: {
                                if (popout.closePopout)
                                    popout.closePopout();
                            }
                        }
                    }
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingM
                    visible: root.modemState !== "off"

                    StatTile {
                        width: (parent.width - Theme.spacingM) / 2
                        label: "Downloaded"
                        value: root.formatBytes(root.rxBytes)
                    }

                    StatTile {
                        width: (parent.width - Theme.spacingM) / 2
                        label: "Uploaded"
                        value: root.formatBytes(root.txBytes)
                    }
                }

                StyledText {
                    visible: root.actionError !== ""
                    width: parent.width
                    text: root.actionError
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    wrapMode: Text.WordWrap
                }

                ActionButton {
                    width: parent.width
                    visible: root.unitState !== "active"
                    accent: true
                    iconName: root.failed ? "refresh" : "link"
                    label: root.failed ? "Retry" : "Connect"
                    onClicked: root.control(root.failed ? "restart" : "start")
                }

                ActionButton {
                    // stop also works when the modem is powered on but not connected
                    width: parent.width
                    visible: root.unitState === "active" || root.modemState !== "off"
                    iconName: "link_off"
                    label: "Disconnect"
                    onClicked: root.control("stop")
                }
            }
        }
    }
}
