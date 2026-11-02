import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

const PAGE_COUNT = 3;          // 0 main, 1 body, 2 splits
const SPLIT_POPUP_MS = 4000;   // how long the split is shown after a punch

// Course overprint colour, used for every course symbol (start, controls, finish, progress)
const ACCENT = 0xFF00FF;
const MUTED = Graphics.COLOR_LT_GRAY;
const DIM = Graphics.COLOR_DK_GRAY;

// Race mode screens. Deliberately no map, position or bearing (IOF-legal).
class RaceView extends WatchUi.View {

    var page as Number = 0;
    private var _race as RaceSession;
    private var _timer as Timer.Timer;

    // set each frame
    private var _w as Number = 0;
    private var _h as Number = 0;
    private var _cx as Number = 0;
    private var _cy as Number = 0;

    function initialize(race as RaceSession) {
        View.initialize();
        _race = race;
        _timer = new Timer.Timer();
    }

    function onShow() as Void {
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function nextPage(step as Number) as Void {
        page = (page + step + PAGE_COUNT) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setAntiAlias(true);

        switch (_race.state) {
            case STATE_IDLE:
                drawPreStart(dc);
                return;
            case STATE_DONE:
                drawDone(dc);
                return;
        }

        drawProgressRing(dc);
        if (System.getTimer() - _race.lastPunchAt < SPLIT_POPUP_MS) {
            drawSplitPopup(dc);
            return;
        }
        drawStatus(dc);
        if (page == 0) {
            drawMain(dc);
        } else if (page == 1) {
            drawBody(dc);
        } else {
            drawSplits(dc);
        }
        drawPageDots(dc);
    }

    // --- screens ---

    private function drawPreStart(dc as Graphics.Dc) as Void {
        var gps = gpsStatus();
        var ready = _race.gpsAccuracy == Position.QUALITY_GOOD || _race.gpsAccuracy == Position.QUALITY_USABLE;

        // START button cue on the bezel (upper right)
        dc.setPenWidth(6);
        dc.setColor(ready ? Graphics.COLOR_GREEN : DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(_cx, _cy, _cx - 4, Graphics.ARC_COUNTER_CLOCKWISE, 18, 42);

        drawStartTriangle(dc, _cx, y(0.21), 34);
        text(dc, _cx, y(0.38), Graphics.FONT_SMALL, "Orienteering", Graphics.COLOR_WHITE);

        // GPS: dot + label, centred as a group
        var label = "GPS " + gps[0];
        var tw = dc.getTextWidthInPixels(label, Graphics.FONT_TINY);
        var gx = _cx - (tw + 14) / 2;
        dc.setColor(gps[1], Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx + 4, y(0.535), 5);
        textLeft(dc, gx + 14, y(0.535), Graphics.FONT_TINY, label, Graphics.COLOR_WHITE);

        var n = _race.numControls;
        text(dc, _cx, y(0.64), Graphics.FONT_TINY, n > 0 ? n.format("%d") + " controls" : "Controls not set", MUTED);

        text(dc, _cx, y(0.79), Graphics.FONT_XTINY, "Press START", MUTED);
        text(dc, _cx, y(0.87), Graphics.FONT_XTINY, "hold UP for settings", DIM);
    }

    private function drawMain(dc as Graphics.Dc) as Void {
        drawTarget(dc, _cx, y(0.255));

        text(dc, _cx, y(0.475), Graphics.FONT_NUMBER_HOT, formatTime(_race.legMs()), Graphics.COLOR_WHITE);
        text(dc, _cx, y(0.625), Graphics.FONT_XTINY, "LEG", DIM);

        text(dc, _cx, y(0.75), Graphics.FONT_NUMBER_MILD, formatTime(_race.timerMs()), MUTED);
        text(dc, _cx, y(0.86), Graphics.FONT_XTINY, "TOTAL", DIM);
    }

    private function drawBody(dc as Graphics.Dc) as Void {
        var hr = _race.heartRate();
        var zone = hr != null ? _race.heartRateZone(hr) : 0;

        text(dc, _cx, y(0.34), Graphics.FONT_NUMBER_HOT, hr != null ? hr.format("%d") : "--", zoneColor(zone));
        text(dc, _cx, y(0.49), Graphics.FONT_XTINY, zone > 0 ? "BPM  ·  Z" + zone.format("%d") : "BPM", DIM);

        dc.setPenWidth(1);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_cx, y(0.61), _cx, y(0.83));

        text(dc, x(0.32), y(0.68), Graphics.FONT_NUMBER_MILD, formatDist(_race.legDistanceM()), Graphics.COLOR_WHITE);
        text(dc, x(0.32), y(0.79), Graphics.FONT_XTINY, "LEG KM", DIM);
        text(dc, x(0.68), y(0.68), Graphics.FONT_NUMBER_MILD, formatDist(_race.distanceM()), MUTED);
        text(dc, x(0.68), y(0.79), Graphics.FONT_XTINY, "TOTAL KM", DIM);
    }

    private function drawSplits(dc as Graphics.Dc) as Void {
        var n = _race.splits.size();
        if (n == 0) {
            text(dc, _cx, _cy, Graphics.FONT_TINY, "No splits yet", MUTED);
            return;
        }
        // last 5, newest on top
        var rows = n < 5 ? n : 5;
        for (var i = 0; i < rows; i++) {
            var idx = n - 1 - i;
            var ry = y(0.26) + i * y(0.125);
            var newest = i == 0;
            drawControl(dc, x(0.36), ry, 13, (idx + 1).format("%d"), newest ? ACCENT : DIM,
                newest ? Graphics.COLOR_WHITE : MUTED, Graphics.FONT_XTINY);
            textLeft(dc, x(0.47), ry, Graphics.FONT_SMALL, formatTime(_race.splits[idx]),
                newest ? Graphics.COLOR_WHITE : MUTED);
        }
    }

    private function drawSplitPopup(dc as Graphics.Dc) as Void {
        var split = _race.lastSplitMs();
        drawControl(dc, _cx, y(0.27), 34, _race.punched.format("%d"), ACCENT, Graphics.COLOR_WHITE,
            Graphics.FONT_MEDIUM);
        text(dc, _cx, y(0.56), Graphics.FONT_NUMBER_HOT, split != null ? formatTime(split) : "--",
            Graphics.COLOR_WHITE);
        var next = _race.targetLabel();
        text(dc, _cx, y(0.76), Graphics.FONT_TINY, next.equals("F") ? "to finish" : "next " + next, MUTED);
    }

    private function drawDone(dc as Graphics.Dc) as Void {
        if (_race.saved) {
            dc.setPenWidth(4);
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(_cx, _cy, _cx - 3);
        }
        drawFinish(dc, _cx, y(0.22), 17);
        text(dc, _cx, y(0.45), Graphics.FONT_NUMBER_HOT, formatTime(_race.timerMs()), Graphics.COLOR_WHITE);
        text(dc, _cx, y(0.635), Graphics.FONT_TINY, _race.punched.format("%d") + " controls", MUTED);
        text(dc, _cx, y(0.735), Graphics.FONT_XTINY, _race.saved ? "Saved" : "Discarded",
            _race.saved ? Graphics.COLOR_GREEN : Graphics.COLOR_RED);
        text(dc, _cx, y(0.85), Graphics.FONT_XTINY, "BACK to exit", DIM);
    }

    // --- shared pieces ---

    // Clock, or PAUSED, at the top
    private function drawStatus(dc as Graphics.Dc) as Void {
        if (_race.state == STATE_PAUSED) {
            text(dc, _cx, y(0.10), Graphics.FONT_XTINY, "PAUSED", Graphics.COLOR_YELLOW);
            return;
        }
        var t = System.getClockTime();
        var hour = t.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12 == 0 ? 12 : hour % 12;
        }
        text(dc, _cx, y(0.10), Graphics.FONT_XTINY, hour.format("%d") + ":" + t.min.format("%02d"), MUTED);
    }

    // Course progress around the bezel; whole ring yellow while paused
    private function drawProgressRing(dc as Graphics.Dc) as Void {
        var r = _cx - 3;
        dc.setPenWidth(4);
        if (_race.state == STATE_PAUSED) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(_cx, _cy, r);
            return;
        }
        var total = _race.numControls;
        if (total <= 0) {
            return;
        }
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_cx, _cy, r);
        var done = _race.punched < total ? _race.punched : total;
        if (done > 0) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            if (done == total) {
                dc.drawCircle(_cx, _cy, r);
            } else {
                var end = 90 - (360 * done / total);
                dc.drawArc(_cx, _cy, r, Graphics.ARC_CLOCKWISE, 90, end);
            }
        }
    }

    // Next control as a course symbol: circle with number (+ "/14"), or finish
    private function drawTarget(dc as Graphics.Dc, tx as Number, ty as Number) as Void {
        var label = _race.targetLabel();
        if (label.equals("F")) {
            drawFinish(dc, tx - 34, ty, 14);
            textLeft(dc, tx - 12, ty, Graphics.FONT_TINY, "FINISH", Graphics.COLOR_WHITE);
            return;
        }
        var next = (_race.punched + 1).format("%d");
        if (_race.numControls > 0) {
            var of = "/" + _race.numControls.format("%d");
            drawControl(dc, tx - 14, ty, 19, next, ACCENT, Graphics.COLOR_WHITE, Graphics.FONT_TINY);
            textLeft(dc, tx + 10, ty, Graphics.FONT_TINY, of, DIM);
        } else {
            drawControl(dc, tx, ty, 19, next, ACCENT, Graphics.COLOR_WHITE, Graphics.FONT_TINY);
        }
    }

    private function drawPageDots(dc as Graphics.Dc) as Void {
        var r = _cx - 15;
        for (var i = 0; i < PAGE_COUNT; i++) {
            var a = Math.toRadians(180 + (i - 1) * 9);
            var px = _cx + r * Math.cos(a);
            var py = _cy - r * Math.sin(a);
            dc.setColor(i == page ? Graphics.COLOR_WHITE : DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(px, py, 3);
        }
    }

    private function drawControl(dc as Graphics.Dc, px as Number, py as Number, r as Number, label as String,
                                 ring as Graphics.ColorType, fg as Graphics.ColorType,
                                 font as Graphics.FontDefinition) as Void {
        dc.setPenWidth(r > 20 ? 4 : 3);
        dc.setColor(ring, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(px, py, r);
        text(dc, px, py, font, label, fg);
    }

    private function drawStartTriangle(dc as Graphics.Dc, px as Number, py as Number, side as Number) as Void {
        var hgt = side * 0.866;
        var top = [px, py - hgt * 2 / 3];
        var left = [px - side / 2, py + hgt / 3];
        var right = [px + side / 2, py + hgt / 3];
        dc.setPenWidth(3);
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(top[0], top[1], left[0], left[1]);
        dc.drawLine(left[0], left[1], right[0], right[1]);
        dc.drawLine(right[0], right[1], top[0], top[1]);
    }

    private function drawFinish(dc as Graphics.Dc, px as Number, py as Number, r as Number) as Void {
        dc.setPenWidth(3);
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(px, py, r);
        dc.drawCircle(px, py, r * 2 / 3);
    }

    // --- helpers ---

    private function x(f as Float) as Number {
        return (_w * f).toNumber();
    }

    private function y(f as Float) as Number {
        return (_h * f).toNumber();
    }

    private function text(dc as Graphics.Dc, px as Numeric, py as Numeric, font as Graphics.FontDefinition,
                          s as String, color as Graphics.ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px, py, font, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function textLeft(dc as Graphics.Dc, px as Numeric, py as Numeric, font as Graphics.FontDefinition,
                              s as String, color as Graphics.ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px, py, font, s, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function gpsStatus() as [String, Graphics.ColorType] {
        switch (_race.gpsAccuracy) {
            case Position.QUALITY_GOOD:
                return ["ready", Graphics.COLOR_GREEN];
            case Position.QUALITY_USABLE:
                return ["ok", Graphics.COLOR_YELLOW];
            default:
                return ["searching", Graphics.COLOR_RED];
        }
    }

    private function zoneColor(zone as Number) as Graphics.ColorType {
        switch (zone) {
            case 1: return MUTED;
            case 2: return Graphics.COLOR_BLUE;
            case 3: return Graphics.COLOR_GREEN;
            case 4: return Graphics.COLOR_ORANGE;
            case 5: return Graphics.COLOR_RED;
            default: return Graphics.COLOR_WHITE;
        }
    }
}

function formatTime(ms as Number) as String {
    var s = ms / 1000;
    var hh = s / 3600;
    var mm = (s % 3600) / 60;
    var ss = s % 60;
    if (hh > 0) {
        return hh.format("%d") + ":" + mm.format("%02d") + ":" + ss.format("%02d");
    }
    return mm.format("%d") + ":" + ss.format("%02d");
}

function formatDist(m as Float) as String {
    return (m / 1000.0).format("%.2f");
}
