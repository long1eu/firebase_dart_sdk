// File created by
// Lung Razvan <long1eu>
// on 03/03/2020

part of '../google_sign_in_dartio.dart';

Future<void> _sendData(HttpRequest request, Object data,
    [String contentType = 'text/html']) async {
  request.response
    ..statusCode = 200
    ..headers.set('content-type', contentType)
    ..write(data);
  await request.response.close();
}

Future<T> _sendErrorAndThrow<T>(HttpRequest request, String message) async {
  request.response
    ..statusCode = 500
    ..headers.set('content-type', 'text/plain')
    ..write(message);
  await request.response.close();

  return Future<T>.error(message);
}

final Uint8List _imageData = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAACY0lEQVR4AcWTA6xcQRhGn20rqm2bMRs3rM2wtm0zqhHUtqI6qm0s3ur+/Wa9/+Ji9qVJTjA652ISiCg2exP6gyZ8PF5oCZgOboHk/xVwEBCYGmGuFehS1wHPvQEW0JDNLQfH4xrABNnACcjLdZDknUsC74ELNKirgE6AGJO8cwODxraIsUgod5qmyASMjBBgAvXB/qAxCygJ23+vSROwXSZgEyCObVPKI8e2ZAsbn8PkzcEn8Eom4EakgN+Lssi0IoOPfwWZXnkb8AUQUOxXWuTqDRDyRPAnwtPT99m59GNOLim7EnnEKAjbgW+AfDivN+9sJKABIM6vhdnuAIFlbVro/KGstxD+BBSM62azoUYCBnF57cZUv1zwc3420R6fHG//TiMhDAM3YZWRgHnBciESQohDEJ8ET87lnNNGAk4GB1jXp4XJBeatRWpywVsjAS99cmVPIv2clxMm/7OhlJTbjYVAFdyEfM0BkBaEPP3atHD5RsjvqMuDbkI3PQG9/U+/O5F+zA19+r+bSonU5fwmjNQTMNEXYFmdHirfUqZX7rsJa/UE7ALk2oWnn5MTkG+F/K52KeO8noAHgMwr0wPybeUycsFHTQEQpwCra2cSfZ/jkZt2yMl9OK60KNIS0AyQaXmGR76rQkbKb0JPLQGDnduT3HLzbkk5w3Wr2RgtAcv/Lssk895KeSlDudtko2qAfUvKbdPe6rjL8fRku9jysmqAaU+N03q2lVgsNsVLTOJM8EU1AIv6gCuAJEK4WHAF9FEJkAzRIeYB0iF6xTzAaIhhMQ8wHKJTLB/AQ5hYN/8Am8FSntayj78AAAAASUVORK5CYII=');

const String _verifyQueryHtml = '''<!DOCTYPE html>
<html class="mdl-js" lang="en">
<head>
    <title>Check</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <script type="text/javascript">
        function init() {
            window.location = window.location.href.replace('?', 'response?');
        }

        window.onload = init;
    </script>
    <style>.mdl-card{display:flex;flex-direction:column;font-size:16px;font-weight:400;min-height:200px;overflow:hidden;width:330px;z-index:1;position:relative;background:#fff;border-radius:2px;box-sizing:border-box}.mdl-card__title{align-items:center;color:#000;display:block;display:flex;justify-content:stretch;line-height:normal;padding:16px 16px;perspective-origin:165px 56px;transform-origin:165px 56px;box-sizing:border-box}.mdl-card__title-text{align-self:flex-end;color:inherit;display:block;display:flex;font-size:24px;font-weight:300;line-height:normal;overflow:hidden;transform-origin:149px 48px;margin:0}.mdl-button{background:0 0;border:none;border-radius:2px;color:#000;position:relative;height:36px;margin:0;min-width:64px;padding:0 16px;display:inline-block;font-family:Roboto,Helvetica,Arial,sans-serif;font-size:14px;font-weight:500;text-transform:uppercase;line-height:1;letter-spacing:0;overflow:hidden;will-change:box-shadow;transition:box-shadow .2s cubic-bezier(.4,0,1,1),background-color .2s cubic-bezier(.4,0,.2,1),color .2s cubic-bezier(.4,0,.2,1);outline:0;cursor:pointer;text-decoration:none;text-align:center;line-height:36px;vertical-align:middle}.mdl-button::-moz-focus-inner{border:0}.mdl-button:hover{background-color:rgba(158,158,158,.2)}.mdl-button:focus:not(:active){background-color:rgba(0,0,0,.12)}.mdl-button:active{background-color:rgba(158,158,158,.4)}.mdl-button.mdl-button--disabled.mdl-button--disabled,.mdl-button[disabled][disabled]{color:rgba(0,0,0,.26);cursor:default;background-color:transparent}.mdl-progress{display:block;position:relative;height:4px;width:500px;max-width:100%}.mdl-progress>.bar{display:block;position:absolute;top:0;bottom:0;width:0;transition:width .2s cubic-bezier(.4,0,.2,1)}.mdl-progress>.progressbar{background-color:#3f51b5;z-index:1;left:0}.mdl-progress>.bufferbar{background-image:linear-gradient(to right,rgba(255,255,255,.7),rgba(255,255,255,.7)),linear-gradient(to right,#3f51b5 ,#3f51b5);z-index:0;left:0}.mdl-progress>.auxbar{right:0}@supports (-webkit-appearance:none){.mdl-progress:not(.mdl-progress--indeterminate):not(.mdl-progress--indeterminate)>.auxbar,.mdl-progress:not(.mdl-progress__indeterminate):not(.mdl-progress__indeterminate)>.auxbar{background-image:linear-gradient(to right,rgba(255,255,255,.7),rgba(255,255,255,.7)),linear-gradient(to right,#3f51b5 ,#3f51b5);mask:url(data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIj8+Cjxzdmcgd2lkdGg9IjEyIiBoZWlnaHQ9IjQiIHZpZXdQb3J0PSIwIDAgMTIgNCIgdmVyc2lvbj0iMS4xIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgogIDxlbGxpcHNlIGN4PSIyIiBjeT0iMiIgcng9IjIiIHJ5PSIyIj4KICAgIDxhbmltYXRlIGF0dHJpYnV0ZU5hbWU9ImN4IiBmcm9tPSIyIiB0bz0iLTEwIiBkdXI9IjAuNnMiIHJlcGVhdENvdW50PSJpbmRlZmluaXRlIiAvPgogIDwvZWxsaXBzZT4KICA8ZWxsaXBzZSBjeD0iMTQiIGN5PSIyIiByeD0iMiIgcnk9IjIiIGNsYXNzPSJsb2FkZXIiPgogICAgPGFuaW1hdGUgYXR0cmlidXRlTmFtZT0iY3giIGZyb209IjE0IiB0bz0iMiIgZHVyPSIwLjZzIiByZXBlYXRDb3VudD0iaW5kZWZpbml0ZSIgLz4KICA8L2VsbGlwc2U+Cjwvc3ZnPgo=)}}.mdl-progress:not(.mdl-progress--indeterminate)>.auxbar,.mdl-progress:not(.mdl-progress__indeterminate)>.auxbar{background-image:linear-gradient(to right,rgba(255,255,255,.9),rgba(255,255,255,.9)),linear-gradient(to right,#3f51b5 ,#3f51b5)}.mdl-progress.mdl-progress--indeterminate>.bar1,.mdl-progress.mdl-progress__indeterminate>.bar1{background-color:#3f51b5;animation-name:indeterminate1;animation-duration:2s;animation-iteration-count:infinite;animation-timing-function:linear}.mdl-progress.mdl-progress--indeterminate>.bar3,.mdl-progress.mdl-progress__indeterminate>.bar3{background-image:none;background-color:#3f51b5;animation-name:indeterminate2;animation-duration:2s;animation-iteration-count:infinite;animation-timing-function:linear}@keyframes indeterminate1{0%{left:0;width:0}50%{left:25%;width:75%}75%{left:100%;width:0}}@keyframes indeterminate2{0%{left:0;width:0}50%{left:0;width:0}75%{left:0;width:25%}100%{left:100%;width:0}}.firebase-container{background-color:#fff;box-sizing:border-box;-moz-box-sizing:border-box;-webkit-box-sizing:border-box;color:rgba(0,0,0,.87);direction:ltr;font:16px Roboto,arial,sans-serif;margin:0 auto;max-width:360px;overflow:hidden;padding-top:8px;position:relative;width:100%}.firebase-progress-bar{height:5px;left:0;position:absolute;top:0;width:100%}.firebase-hidden-button{height:1px;visibility:hidden;width:1px}.firebase-container#app-verification-screen{top:100px}.firebase-title{color:rgba(0,0,0,.87);direction:ltr;font-size:24px;font-weight:500;line-height:24px;margin:0;padding:0;text-align:center}.firebase-middle-progress-bar{height:5px;margin-left:auto;margin-right:auto;top:20px;width:250px}.firebase-hidden{display:none}@media (max-width:520px){.firebase-container{box-shadow:none;max-width:none;width:100%}}body{margin:0}.firebase-container{background-color:#fff;box-sizing:border-box;-moz-box-sizing:border-box;-webkit-box-sizing:border-box;color:rgba(0,0,0,.87);direction:ltr;font:16px Roboto,arial,sans-serif;margin:0 auto;max-width:360px;overflow:hidden;padding-top:8px;position:relative;width:100%}.firebase-progress-bar{height:5px;left:0;position:absolute;top:0;width:100%}.firebase-hidden-button{height:1px;visibility:hidden;width:1px}.firebase-container#app-verification-screen{top:100px}.firebase-title{color:rgba(0,0,0,.87);direction:ltr;font-size:24px;font-weight:500;line-height:24px;margin:0;padding:0;text-align:center}.firebase-middle-progress-bar{height:5px;margin-left:auto;margin-right:auto;top:20px;width:250px}.firebase-hidden{display:none}@media (max-width:520px){.firebase-container{box-shadow:none;max-width:none;width:100%}}</style>
</head>
<body>

<div id="progressBarContainer"></div>
<div>
    <div id="app-verification-screen" class="mdl-card mdl-shadow--2dp firebase-container">
        <button id="verify" class="mdl-button firebase-hidden-button" disabled="">Verify</button>
        <div id="status-container"><h1 class="firebase-title" id="status-container-label">Verifying your credentials...</h1>
            <div id="app-verification-progress-bar"
                 class="mdl-progress mdl-js-progress mdl-progress__indeterminate firebase-middle-progress-bar is-upgraded"
                 data-upgraded=",MaterialProgress">
                <div class="progressbar bar bar1" style="width: 0%;"></div>
                <div class="bufferbar bar bar2" style="width: 100%;"></div>
                <div class="auxbar bar bar3" style="width: 0%;"></div>
            </div>
        </div>
    </div>
</div>
</body>
</html>''';

const String _verifyFragmentHtml = '''<!DOCTYPE html>
<html class="mdl-js" lang="en">
<head>
    <title>Check</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <script type="text/javascript">
        function init() {
            window.location = window.location.href.replace('#', 'response?');
        }

        window.onload = init;
    </script>
    <style>.mdl-card{display:flex;flex-direction:column;font-size:16px;font-weight:400;min-height:200px;overflow:hidden;width:330px;z-index:1;position:relative;background:#fff;border-radius:2px;box-sizing:border-box}.mdl-card__title{align-items:center;color:#000;display:block;display:flex;justify-content:stretch;line-height:normal;padding:16px 16px;perspective-origin:165px 56px;transform-origin:165px 56px;box-sizing:border-box}.mdl-card__title-text{align-self:flex-end;color:inherit;display:block;display:flex;font-size:24px;font-weight:300;line-height:normal;overflow:hidden;transform-origin:149px 48px;margin:0}.mdl-button{background:0 0;border:none;border-radius:2px;color:#000;position:relative;height:36px;margin:0;min-width:64px;padding:0 16px;display:inline-block;font-family:Roboto,Helvetica,Arial,sans-serif;font-size:14px;font-weight:500;text-transform:uppercase;line-height:1;letter-spacing:0;overflow:hidden;will-change:box-shadow;transition:box-shadow .2s cubic-bezier(.4,0,1,1),background-color .2s cubic-bezier(.4,0,.2,1),color .2s cubic-bezier(.4,0,.2,1);outline:0;cursor:pointer;text-decoration:none;text-align:center;line-height:36px;vertical-align:middle}.mdl-button::-moz-focus-inner{border:0}.mdl-button:hover{background-color:rgba(158,158,158,.2)}.mdl-button:focus:not(:active){background-color:rgba(0,0,0,.12)}.mdl-button:active{background-color:rgba(158,158,158,.4)}.mdl-button.mdl-button--disabled.mdl-button--disabled,.mdl-button[disabled][disabled]{color:rgba(0,0,0,.26);cursor:default;background-color:transparent}.mdl-progress{display:block;position:relative;height:4px;width:500px;max-width:100%}.mdl-progress>.bar{display:block;position:absolute;top:0;bottom:0;width:0;transition:width .2s cubic-bezier(.4,0,.2,1)}.mdl-progress>.progressbar{background-color:#3f51b5;z-index:1;left:0}.mdl-progress>.bufferbar{background-image:linear-gradient(to right,rgba(255,255,255,.7),rgba(255,255,255,.7)),linear-gradient(to right,#3f51b5 ,#3f51b5);z-index:0;left:0}.mdl-progress>.auxbar{right:0}@supports (-webkit-appearance:none){.mdl-progress:not(.mdl-progress--indeterminate):not(.mdl-progress--indeterminate)>.auxbar,.mdl-progress:not(.mdl-progress__indeterminate):not(.mdl-progress__indeterminate)>.auxbar{background-image:linear-gradient(to right,rgba(255,255,255,.7),rgba(255,255,255,.7)),linear-gradient(to right,#3f51b5 ,#3f51b5);mask:url(data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIj8+Cjxzdmcgd2lkdGg9IjEyIiBoZWlnaHQ9IjQiIHZpZXdQb3J0PSIwIDAgMTIgNCIgdmVyc2lvbj0iMS4xIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgogIDxlbGxpcHNlIGN4PSIyIiBjeT0iMiIgcng9IjIiIHJ5PSIyIj4KICAgIDxhbmltYXRlIGF0dHJpYnV0ZU5hbWU9ImN4IiBmcm9tPSIyIiB0bz0iLTEwIiBkdXI9IjAuNnMiIHJlcGVhdENvdW50PSJpbmRlZmluaXRlIiAvPgogIDwvZWxsaXBzZT4KICA8ZWxsaXBzZSBjeD0iMTQiIGN5PSIyIiByeD0iMiIgcnk9IjIiIGNsYXNzPSJsb2FkZXIiPgogICAgPGFuaW1hdGUgYXR0cmlidXRlTmFtZT0iY3giIGZyb209IjE0IiB0bz0iMiIgZHVyPSIwLjZzIiByZXBlYXRDb3VudD0iaW5kZWZpbml0ZSIgLz4KICA8L2VsbGlwc2U+Cjwvc3ZnPgo=)}}.mdl-progress:not(.mdl-progress--indeterminate)>.auxbar,.mdl-progress:not(.mdl-progress__indeterminate)>.auxbar{background-image:linear-gradient(to right,rgba(255,255,255,.9),rgba(255,255,255,.9)),linear-gradient(to right,#3f51b5 ,#3f51b5)}.mdl-progress.mdl-progress--indeterminate>.bar1,.mdl-progress.mdl-progress__indeterminate>.bar1{background-color:#3f51b5;animation-name:indeterminate1;animation-duration:2s;animation-iteration-count:infinite;animation-timing-function:linear}.mdl-progress.mdl-progress--indeterminate>.bar3,.mdl-progress.mdl-progress__indeterminate>.bar3{background-image:none;background-color:#3f51b5;animation-name:indeterminate2;animation-duration:2s;animation-iteration-count:infinite;animation-timing-function:linear}@keyframes indeterminate1{0%{left:0;width:0}50%{left:25%;width:75%}75%{left:100%;width:0}}@keyframes indeterminate2{0%{left:0;width:0}50%{left:0;width:0}75%{left:0;width:25%}100%{left:100%;width:0}}.firebase-container{background-color:#fff;box-sizing:border-box;-moz-box-sizing:border-box;-webkit-box-sizing:border-box;color:rgba(0,0,0,.87);direction:ltr;font:16px Roboto,arial,sans-serif;margin:0 auto;max-width:360px;overflow:hidden;padding-top:8px;position:relative;width:100%}.firebase-progress-bar{height:5px;left:0;position:absolute;top:0;width:100%}.firebase-hidden-button{height:1px;visibility:hidden;width:1px}.firebase-container#app-verification-screen{top:100px}.firebase-title{color:rgba(0,0,0,.87);direction:ltr;font-size:24px;font-weight:500;line-height:24px;margin:0;padding:0;text-align:center}.firebase-middle-progress-bar{height:5px;margin-left:auto;margin-right:auto;top:20px;width:250px}.firebase-hidden{display:none}@media (max-width:520px){.firebase-container{box-shadow:none;max-width:none;width:100%}}body{margin:0}.firebase-container{background-color:#fff;box-sizing:border-box;-moz-box-sizing:border-box;-webkit-box-sizing:border-box;color:rgba(0,0,0,.87);direction:ltr;font:16px Roboto,arial,sans-serif;margin:0 auto;max-width:360px;overflow:hidden;padding-top:8px;position:relative;width:100%}.firebase-progress-bar{height:5px;left:0;position:absolute;top:0;width:100%}.firebase-hidden-button{height:1px;visibility:hidden;width:1px}.firebase-container#app-verification-screen{top:100px}.firebase-title{color:rgba(0,0,0,.87);direction:ltr;font-size:24px;font-weight:500;line-height:24px;margin:0;padding:0;text-align:center}.firebase-middle-progress-bar{height:5px;margin-left:auto;margin-right:auto;top:20px;width:250px}.firebase-hidden{display:none}@media (max-width:520px){.firebase-container{box-shadow:none;max-width:none;width:100%}}</style>
</head>
<body>

<div id="progressBarContainer"></div>
<div>
    <div id="app-verification-screen" class="mdl-card mdl-shadow--2dp firebase-container">
        <button id="verify" class="mdl-button firebase-hidden-button" disabled="">Verify</button>
        <div id="status-container"><h1 class="firebase-title" id="status-container-label">Verifying your credentials...</h1>
            <div id="app-verification-progress-bar"
                 class="mdl-progress mdl-js-progress mdl-progress__indeterminate firebase-middle-progress-bar is-upgraded"
                 data-upgraded=",MaterialProgress">
                <div class="progressbar bar bar1" style="width: 0%;"></div>
                <div class="bufferbar bar bar2" style="width: 100%;"></div>
                <div class="auxbar bar bar3" style="width: 0%;"></div>
            </div>
        </div>
    </div>
</div>
</body>
</html>''';

const String _successHtml = '''<!DOCTYPE html>
<html class="mdl-js">
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
    <style>.mdl-card{display:flex;flex-direction:column;font-size:16px;font-weight:400;min-height:200px;overflow:hidden;width:330px;z-index:1;position:relative;background:#fff;border-radius:2px;box-sizing:border-box}.mdl-card__title{align-items:center;color:#000;display:block;display:flex;justify-content:stretch;line-height:normal;padding:16px 16px;perspective-origin:165px 56px;transform-origin:165px 56px;box-sizing:border-box}.mdl-card__title-text{align-self:flex-end;color:inherit;display:block;display:flex;font-size:24px;font-weight:300;line-height:normal;overflow:hidden;transform-origin:149px 48px;margin:0}.mdl-card__subtitle-text{font-size:14px;color:rgba(0,0,0,.54);margin:0;text-align:center}@supports (-webkit-appearance:none){.mdl-progress:not(.mdl-progress--indeterminate):not(.mdl-progress--indeterminate)>.auxbar,.mdl-progress:not(.mdl-progress__indeterminate):not(.mdl-progress__indeterminate)>.auxbar{background-image:linear-gradient(to right,rgba(255,255,255,.7),rgba(255,255,255,.7)),linear-gradient(to right,#3f51b5 ,#3f51b5);mask:url(data:image/svg+xml;base64,PD94bWwgdmVyc2lvbj0iMS4wIj8+Cjxzdmcgd2lkdGg9IjEyIiBoZWlnaHQ9IjQiIHZpZXdQb3J0PSIwIDAgMTIgNCIgdmVyc2lvbj0iMS4xIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciPgogIDxlbGxpcHNlIGN4PSIyIiBjeT0iMiIgcng9IjIiIHJ5PSIyIj4KICAgIDxhbmltYXRlIGF0dHJpYnV0ZU5hbWU9ImN4IiBmcm9tPSIyIiB0bz0iLTEwIiBkdXI9IjAuNnMiIHJlcGVhdENvdW50PSJpbmRlZmluaXRlIiAvPgogIDwvZWxsaXBzZT4KICA8ZWxsaXBzZSBjeD0iMTQiIGN5PSIyIiByeD0iMiIgcnk9IjIiIGNsYXNzPSJsb2FkZXIiPgogICAgPGFuaW1hdGUgYXR0cmlidXRlTmFtZT0iY3giIGZyb209IjE0IiB0bz0iMiIgZHVyPSIwLjZzIiByZXBlYXRDb3VudD0iaW5kZWZpbml0ZSIgLz4KICA8L2VsbGlwc2U+Cjwvc3ZnPgo=)}}@keyframes indeterminate1{0%{left:0;width:0}50%{left:25%;width:75%}75%{left:100%;width:0}}@keyframes indeterminate2{0%{left:0;width:0}50%{left:0;width:0}75%{left:0;width:25%}100%{left:100%;width:0}}.firebase-container{background-color:#fff;box-sizing:border-box;-moz-box-sizing:border-box;-webkit-box-sizing:border-box;color:rgba(0,0,0,.87);direction:ltr;font:16px Roboto,arial,sans-serif;margin:0 auto;max-width:360px;overflow:hidden;padding-top:8px;position:relative;width:100%}.firebase-container#app-verification-screen{top:100px}.firebase-title{color:rgba(0,0,0,.87);direction:ltr;font-size:24px;font-weight:500;line-height:24px;margin:0;padding:0;text-align:center}@media (max-width:520px){.firebase-container{box-shadow:none;max-width:none;width:100%}}body{margin:0}.firebase-container{background-color:#fff;box-sizing:border-box;-moz-box-sizing:border-box;-webkit-box-sizing:border-box;color:rgba(0,0,0,.87);direction:ltr;font:16px Roboto,arial,sans-serif;margin:0 auto;max-width:360px;overflow:hidden;padding-top:8px;position:relative;width:100%}.firebase-container#app-verification-screen{top:100px}.firebase-title{color:rgba(0,0,0,.87);direction:ltr;font-size:24px;font-weight:500;line-height:24px;margin:0;padding:0;text-align:center}@media (max-width:520px){.firebase-container{box-shadow:none;max-width:none;width:100%}}</style>
</head>
<body>
<div>
    <div id="app-verification-screen" class="mdl-card mdl-shadow--2dp firebase-container">
        <div id="status-container">
            <h1 class="firebase-title" id="status-container-label">Credentials successfully verified.</h1>
            <h6 class="mdl-card__subtitle-text">This window can be closed now.</h6>
        </div>
    </div>
</div>
</body>
</html>''';
