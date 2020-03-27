import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:horstl_wrapper/src/models/dish.dart';
import 'package:horstl_wrapper/src/models/menu.dart';
import 'package:http/http.dart';
import 'package:html/parser.dart';

import 'package:horstl_wrapper/horstl_wrapper.dart';

abstract class Pages {
  static final String HOMEPAGE = '/pages/cs/sys/portal/hisinoneStartPage.faces?page=1';
  static final String LOGIN = '/rds?state=user&type=1&category=auth.login';
  static final String TIME_TABLE = '/pages/plan/individualTimetable.xhtml?_flowId=individualTimetableSchedule-flow';
  static final String MENU = 'http://www.maxmanager.de/daten-extern/sw-giessen/html/speiseplan-render.php';
}

class HorstlScrapper {
  static final String _BASE_URL = 'https://horstl.hs-fulda.de/qisserver';
  String _fdNumber;
  String _passWord;
  String _sessionID;
  final HttpClient _session = HttpClient();

  HorstlScrapper(String fdNumber, String passWord) {
    _fdNumber = fdNumber;
    _passWord = passWord;
  }

  Future<TimeTable> getTimeTable() async {
    var doc = parse(await getTimeTableSrc());

    var greeting = doc.getElementById('hisinoneTitle').text;
    var names = greeting
        .replaceFirst('\n			Stundenplan für ', '')
        .replaceFirst(' ', '')
        .split(',');

    var sureName = names[0].trim();
    var name = names[1].trim();

    var tt = TimeTable(sureName, name);
    var dayLabels = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

    var rawDays = doc.getElementsByClassName('column');
    var currentDay = 0;

    for (var e in rawDays) {
      var courses = e.text
          .replaceFirst('\n' * 2, '')
          .replaceFirst('\n' * 2, '')
          .replaceAll('Durchführende Dozentinnen/Dozenten: ', '\n')
          .replaceAll('Status: ', '\n')
          .split('\n' * 3);

      var dateInfo = courses[0]
          .split('\n').removeAt(0).replaceFirst(' ', '').split(',');
      var dow = dateInfo[0];
      var date = dateInfo[1];
      var day = Day(dow, date);
      tt.days[dayLabels[currentDay]] = day;
      currentDay++;

      for (var c in courses) {
        var courseLines = c.split('\n');
        if (courseLines.length > 2) {
          var idName = courseLines[0].split(' ');
          var kindGroup = courseLines[1].split(',');

          var id = idName[0].trim();
          var name = idName[1];
          if (idName.length > 2) {
            for(var i = 2; i < idName.length; i++) {
              name += ' ${idName[i]}';
            }
          }

          var kind = kindGroup[0].trim();
          var group = kindGroup[1].trim();

          var time = courseLines[2].trim();
          var frequency = courseLines[3].trim();
          var timePeriod = courseLines[4].trim();
          var roomInfo = courseLines[5].trim();
          var docent = courseLines[6].trim();
          var status = courseLines[7].trim();
          var warning;
          var course = Course(id, name, kind, group, time, frequency, timePeriod,
              roomInfo, docent, status, warning);
          day.addCourse(course);
        }
      }
    }
    return tt;
  }

  Future<String> getTimeTableSrc() async {
    if (_sessionID == null) {
      await _authenticate();
    }
    var response = await _session.getUrl(Uri.parse('$_BASE_URL${Pages.TIME_TABLE}'))
        .then((HttpClientRequest request) {
      request.headers.add('Cookie', 'JSESSIONID=$_sessionID');
      return request.close();
    });
    return _readResponse(response, utf8.decoder);
  }

  Future<String> getMenuSrc(DateTime day) async {
    var body = 'func=make_spl&locId=fulda&lang=de&date=${day.year}-${day.month}-${day.day}';
    var httpClient = HttpClient();
    var request = await httpClient.postUrl(Uri.parse(Pages.MENU));
    request.headers.add('content-type', 'application/x-www-form-urlencoded; charset=utf-8');
    request.headers.add('Origin', 'http://www.maxmanager.de');
    request.headers.add('Referer', 'http://www.maxmanager.de/daten-extern/sw-giessen/html/speiseplaene.php?einrichtung=fulda');
    request.headers.add('Content-Length', body.length);
    request.add(utf8.encode(body));
    var response = await request.close();
    return _readResponse(response, utf8.decoder);
  }

  Future<Menu> getMenu(DateTime day) async {
    var menuDoc = parse(await getMenuSrc(day));
    var dishes = menuDoc.getElementsByTagName('tr');
    // Remove navigation
    dishes.removeAt(0);
    var menu = Menu('${day.year}-${day.month}-${day.day}');

    for (var i = 0; i < dishes.length; i++) {
      if (dishes[i].getElementsByClassName('artikel').isNotEmpty) {
        var name = dishes[i].getElementsByClassName('artikel')[0].text
            .trim();
        var description = dishes[i].getElementsByClassName('descr')[0].text
            .trim();
        var price = dishes[i].getElementsByClassName('cell3')[0].text
            .trim();
        var imgURL = 'https://image.freepik.com/free-photo/wooden-texture_1208-334.jpg';
        var imgTag = dishes[i].getElementsByClassName('thumb');
        if (imgTag.isNotEmpty) {
          imgURL = _fixThumbnailURL(imgTag[0].attributes['src']);

        }
        var dish = Dish(name, description, price, imgURL);
        menu.addDish(dish);
      }
    }
    return menu;
  }

  void _authenticate() async {
    var loginURL = '$_BASE_URL${Pages.LOGIN}';
    var cli = Client();
    var formData = {
      'asdf': _fdNumber,
      'fdsa': _passWord,
    };
    var r = await cli.post(loginURL, body: formData);
    var cookies = r.headers['set-cookie'].split(';');
    _sessionID = cookies[0].substring(0, cookies[0].length).split('=')[1];
    // print(_sessionID);
  }

  // Helpers
  Future<String> _readResponse(HttpClientResponse response, StreamTransformerBase<List<int>, String> decoder) {
    var completer = Completer<String>();
    var contents = StringBuffer();
    response.transform(decoder).listen((data) {
      if (data is String) {
        contents.write(data);
      }
    }, onDone: () => completer.complete(contents.toString()));
    return completer.future;
  }

  String _fixThumbnailURL(String url) {
    return url.replaceFirst('/fotos/', '/fotos/big/');
  }
}