import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/douyu_danmaku.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_message.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:html_unescape/html_unescape.dart';

class DouyuSite implements LiveSite {
  @override
  String id = "douyu";

  @override
  String name = "斗鱼直播";

  @override
  LiveDanmaku getDanmaku() => DouyuDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [
      LiveCategory(id: "PCgame", name: "网游竞技", children: []),
      LiveCategory(id: "djry", name: "单机热游", children: []),
      LiveCategory(id: "syxx", name: "手游休闲", children: []),
      LiveCategory(id: "yl", name: "娱乐天地", children: []),
      LiveCategory(id: "yz", name: "颜值", children: []),
      LiveCategory(id: "kjwh", name: "科技文化", children: []),
      LiveCategory(id: "yp", name: "语言互动", children: []),
    ];

    for (var item in categories) {
      var items = await getSubCategories(item.id);
      item.children.addAll(items);
    }
    return categories;
  }

  Future<List<LiveSubCategory>> getSubCategories(String id) async {
    var result = await HttpClient.instance.getJson(
        "https://www.douyu.com/japi/weblist/api/getC2List",
        queryParameters: {"shortName": id, "offset": 0, "limit": 200});

    List<LiveSubCategory> subs = [];
    for (var item in result["data"]["list"]) {
      subs.add(LiveSubCategory(
        pic: item["squareIconUrlW"].toString(),
        id: item["cid2"].toString(),
        parentId: id,
        name: item["cname2"].toString(),
      ));
    }

    return subs;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category,
      {int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/gapi/rkc/directory/mixList/2_${category.id}/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    var data = detail.data.toString();
    data += "&cdn=&rate=-1&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0";
    List<LivePlayQuality> qualities = [];
    var result = await HttpClient.instance.postJson(
      "https://www.douyu.com/lapi/live/getH5Play/${detail.roomId}",
      data: data,
      formUrlEncoded: true,
    );

    var cdns = <String>[];
    for (var item in result["data"]["cdnsWithName"]) {
      cdns.add(item["cdn"].toString());
    }
    for (var item in result["data"]["multirates"]) {
      qualities.add(LivePlayQuality(
        quality: item["name"].toString(),
        data: DouyuPlayData(item["rate"], cdns),
      ));
    }
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    var args = detail.data.toString();
    var data = quality.data as DouyuPlayData;

    List<String> urls = [];
    for (var item in data.cdns) {
      var url = await getPlayUrl(detail.roomId, args, data.rate, item);
      if (url.isNotEmpty) {
        urls.add(url);
      }
    }
    return urls;
  }

  Future<String> getPlayUrl(
      String roomId, String args, int rate, String cdn) async {
    args += "&cdn=$cdn&rate=$rate";
    var result = await HttpClient.instance.postJson(
      "https://www.douyu.com/lapi/live/getH5Play/$roomId",
      data: args,
      header: {
        'referer': 'https://www.douyu.com/$roomId',
        'user-agent':
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43"
      },
      formUrlEncoded: true,
    );

    return "${result["data"]["rtmp_url"]}/${HtmlUnescape().convert(result["data"]["rtmp_live"].toString())}";
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/weblist/apinc/allpage/6/$page",
      queryParameters: {},
    );

    var items = <LiveRoomItem>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoomItem(
        cover: item['rs16'].toString(),
        online: item['ol'],
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        userName: item['nn'].toString(),
      );
      items.add(roomItem);
    }
    var hasMore = page < result['data']['pgcnt'];
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    var result = await HttpClient.instance.getJson(
        "https://m.douyu.com/$roomId/index.pageContext.json",
        queryParameters: {},
        header: {
          'referer': 'https://m.douyu.com/$roomId',
          'user-agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1 Edg/114.0.0.0',
        });
    var roomInfo = result["pageProps"]["room"]["roomInfo"]["roomInfo"];

    var jsEncResult = await HttpClient.instance.getText(
        "https://www.douyu.com/swf_api/homeH5Enc?rids=$roomId",
        queryParameters: {},
        header: {
          'referer': 'https://www.douyu.com/$roomId',
          'user-agent':
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43"
        });
    var crptext = json.decode(jsEncResult)["data"]["room$roomId"].toString();

    return LiveRoomDetail(
      cover: roomInfo["roomSrc"].toString(),
      online: parseHotNum(roomInfo["hn"].toString()),
      roomId: roomInfo["rid"].toString(),
      title: roomInfo["roomName"].toString(),
      userName: roomInfo["nickname"].toString(),
      userAvatar: roomInfo["avatar"].toString(),
      introduction: "",
      notice: roomInfo["notice"].toString(),
      status: roomInfo["isLive"] == 1,
      danmakuData: roomInfo["rid"].toString(),
      data: await getPlayArgs(crptext, roomInfo["rid"].toString()),
      url: "https://www.douyu.com/$roomId",
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchShow",
      queryParameters: {
        "kw": keyword,
        "page": page,
        "pageSize": 20,
      },
      header: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did'
      },
    );
    if (result['error'] != 0) {
      throw Exception(result['msg']);
    }
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["relateShow"]) {
      var roomItem = LiveRoomItem(
        roomId: item["rid"].toString(),
        title: item["roomName"].toString(),
        cover: item["roomSrc"].toString(),
        userName: item["nickName"].toString(),
        online: parseHotNum(item["hot"].toString()),
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["relateShow"].isNotEmpty;
    return LiveSearchRoomResult(hasMore: hasMore, items: items);
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchUser",
      queryParameters: {
        "kw": keyword,
        "page": page,
        "pageSize": 20,
        "filterType": 1,
      },
      header: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did'
      },
    );

    var items = <LiveAnchorItem>[];
    for (var item in result["data"]["relateUser"]) {
      var roomItem = LiveAnchorItem(
        roomId: item["anchorInfo"]["rid"].toString(),
        avatar: item["anchorInfo"]["avatar"].toString(),
        userName: item["anchorInfo"]["nickName"].toString(),
        liveStatus:
            (int.tryParse(item["anchorInfo"]["isLive"].toString()) ?? 0) == 1,
      );
      items.add(roomItem);
    }
    var hasMore = result["data"]["relateUser"].isNotEmpty;
    return LiveSearchAnchorResult(hasMore: hasMore, items: items);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    var detail = await getRoomDetail(roomId: roomId);
    return detail.status;
  }

  Future<String> getPlayArgs(String html, String rid) async {
    //取加密的js
    html = RegExp(
                r"(vdwdae325w_64we[\s\S]*function ub98484234[\s\S]*?)function",
                multiLine: true)
            .firstMatch(html)
            ?.group(1) ??
        "";
    html = html.replaceAll(RegExp(r"eval.*?;}"), "strc;}");

    var result = await HttpClient.instance.postJson(
        "http://alive.nsapps.cn/api/AllLive/DouyuSign",
        data: {"html": html, "rid": rid});

    if (result["code"] == 0) {
      return result["data"].toString();
    }
    return "";
  }

  int parseHotNum(String hn) {
    try {
      var num = double.parse(hn.replaceAll("万", ""));
      if (hn.contains("万")) {
        num *= 10000;
      }
      return num.round();
    } catch (_) {
      return -999;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) {
    //尚不支持
    return Future.value([]);
  }
}

class DouyuPlayData {
  final int rate;
  final List<String> cdns;
  DouyuPlayData(this.rate, this.cdns);
}
