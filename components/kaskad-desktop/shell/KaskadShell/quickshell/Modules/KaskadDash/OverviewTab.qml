import QtQuick
import qs.Common
import qs.Modules.KaskadDash.Overview
import qs.Widgets

Item {
    id: root

    LayoutMirroring.enabled: I18n.isRtl
    LayoutMirroring.childrenInherit: true

    implicitWidth: SettingsData.showWeekNumber ? 736 : 700
    implicitHeight: 424

    readonly property real cardGap: Theme.spacingM
    readonly property real summaryRowHeight: 128
    readonly property real contentRowHeight: implicitHeight - summaryRowHeight - cardGap
    readonly property real clockCardWidth: SettingsData.weatherEnabled ? 200 : width
    readonly property real sideColumnWidth: Math.max(216, Math.min(236, width * 0.31))
    readonly property real profileCardHeight: 128

    signal switchToWeatherTab
    signal closeDash
    signal navFocusRequested

    function handleKeyEvent(event) {
        return calendarLoader.item ? calendarLoader.item.handleKeyEvent(event) : false;
    }

    Column {
        anchors.fill: parent
        spacing: root.cardGap

        Row {
            id: summaryRow

            width: parent.width
            height: root.summaryRowHeight
            spacing: root.cardGap

            ClockCard {
                width: root.clockCardWidth
                height: summaryRow.height
            }

            WeatherOverviewCard {
                width: SettingsData.weatherEnabled ? summaryRow.width - root.clockCardWidth - summaryRow.spacing : 0
                height: summaryRow.height
                visible: SettingsData.weatherEnabled

                onClicked: root.switchToWeatherTab()
            }
        }

        Row {
            id: contentRow

            width: parent.width
            height: root.contentRowHeight
            spacing: root.cardGap

            // The calendar remains primary without swallowing the whole page.
            Loader {
                id: calendarLoader

                width: contentRow.width - root.sideColumnWidth - contentRow.spacing
                height: contentRow.height
                asynchronous: true
                sourceComponent: Component {
                    CalendarOverviewCard {
                        onCloseDash: root.closeDash()
                        onNavFocusRequested: root.navFocusRequested()
                    }
                }

                KaskadSpinner {
                    anchors.centerIn: parent
                    size: 32
                    visible: calendarLoader.status === Loader.Loading
                }
            }

            Column {
                width: root.sideColumnWidth
                height: contentRow.height
                spacing: root.cardGap

                UserInfoCard {
                    width: parent.width
                    height: root.profileCardHeight
                }

                SystemMonitorCard {
                    width: parent.width
                    height: parent.height - root.profileCardHeight - parent.spacing
                }
            }
        }
    }
}
