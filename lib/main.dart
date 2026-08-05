import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart'; // ブラウザ起動用

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const CheapestTravelApp());
}

class CheapestTravelApp extends StatelessWidget {
  const CheapestTravelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '最安旅費ナビ PRO',
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      home: const TravelSearchScreen(),
    );
  }
}

class TravelSearchScreen extends StatefulWidget {
  const TravelSearchScreen({super.key});

  @override
  State<TravelSearchScreen> createState() => _TravelSearchScreenState();
}

class _TravelSearchScreenState extends State<TravelSearchScreen> {
  String departure = '大垣';
  String destination = '沖縄';
  String startDate = '2026-08-05';
  String endDate = '2026-08-08';

  // ★ 人数（デフォルト1人）
  int travelerCount = 1;

  Map<String, dynamic>? bestRoute;
  bool isSearching = false;
  String errorMessage = '';

  // 🔗 URLをブラウザで開く関数
  Future<void> _launchURL(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $url');
    }
  }

  // ーーー 🚃 1. 地上交通（大垣発の固定対応表） ーーー
  Future<Map<String, int>> fetchTrainFares(String fromStation) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return {'NGO': 3480, 'KIX': 7000};
  }

  // ーーー ✈️ 2. 航空券API（SerpApi）連動 ーーー
  Future<Map<String, Map<String, dynamic>>> fetchFlightFares(
    String toLocation,
  ) async {
    final String flightApiKey = dotenv.env['FLIGHT_API_KEY'] ?? '';

    if (flightApiKey.isEmpty) {
      debugPrint('警告: FLIGHT_API_KEYが空です。モックデータを使用します。');
      return _getMockFlightPrices();
    }

    String destCode = 'OKA';
    if (toLocation.contains('沖縄') || toLocation.toUpperCase() == 'OKA') {
      destCode = 'OKA';
    }

    try {
      final results = await Future.wait([
        _requestFlightPrice(flightApiKey, 'NGO', destCode),
        _requestFlightPrice(flightApiKey, 'KIX', destCode),
      ]);

      return {'NGO': results[0], 'KIX': results[1]};
    } catch (e) {
      debugPrint('航空券API通信例外発生: $e');
      return _getMockFlightPrices();
    }
  }

  Future<Map<String, dynamic>> _requestFlightPrice(
    String apiKey,
    String from,
    String to,
  ) async {
    final url = Uri.parse(
      'https://serpapi.com/search.json?engine=google_flights&departure_id=$from&arrival_id=$to&outbound_date=$startDate&return_date=$endDate&currency=JPY&api_key=$apiKey',
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['best_flights'] != null &&
            (data['best_flights'] as List).isNotEmpty) {
          final flight = data['best_flights'][0];

          int price = (flight['price'] as num).toInt();
          String airline = flight['flights']?[0]?['airline'] ?? '航空会社';
          String link =
              flight['link'] ??
              data['search_metadata']?['google_flights_url'] ??
              'https://www.google.com/travel/flights';

          return {'price': price, 'name': airline, 'link': link};
        }
      }
    } catch (e) {
      debugPrint('フライト取得エラー: $e');
    }
    return {
      'price': 0,
      'name': '航空会社未定',
      'link': 'https://www.google.com/travel/flights',
    };
  }

  Map<String, Map<String, dynamic>> _getMockFlightPrices() {
    int dayOffset = int.tryParse(startDate.split('-').last) ?? 5;
    int baseNgo = 28000;
    int baseKix = 25000;
    if (dayOffset != 5) {
      baseNgo = 20000 + (dayOffset * 1500);
      baseKix = 18000 + (dayOffset * 1300);
    }
    return {
      'NGO': {
        'price': baseNgo,
        'name': '救済便A (ANA等)',
        'link': 'https://www.google.com/travel/flights',
      },
      'KIX': {
        'price': baseKix,
        'name': '救済便B (LCC等)',
        'link': 'https://www.google.com/travel/flights',
      },
    };
  }

  // ーーー 🏨 3. ホテルAPI（SerpApi）連動 ーーー
  Future<Map<String, dynamic>> fetchHotelFare(String keyword) async {
    final String apiKey = dotenv.env['FLIGHT_API_KEY'] ?? '';
    final url = Uri.parse(
      'https://serpapi.com/search.json?engine=google_hotels&q=ホテル+$keyword&check_in_date=$startDate&check_out_date=$endDate&currency=JPY&api_key=$apiKey',
    );

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['properties'] != null &&
            (data['properties'] as List).isNotEmpty) {
          List properties = data['properties'];
          Map<String, dynamic>? cheapestHotel;
          int minPrice = 99999999;

          for (var h in properties) {
            String priceString =
                h['rate_per_night']?['lowest']?.toString().replaceAll(
                  RegExp(r'[^0-9]'),
                  '',
                ) ??
                '99999999';
            int price = int.tryParse(priceString) ?? 99999999;

            if (price < minPrice) {
              minPrice = price;

              String hotelLink = h['link'] ?? '';
              if (hotelLink.isEmpty) {
                String hotelNameForSearch = Uri.encodeComponent(
                  h['name'] ?? 'ホテル',
                );
                hotelLink =
                    'https://www.google.com/travel/search?q=$hotelNameForSearch';
              }

              cheapestHotel = {
                'price': price,
                'name': h['name'] ?? '宿泊施設',
                'link': hotelLink,
              };
            }
          }

          if (cheapestHotel != null) return cheapestHotel;
        }
      }
    } catch (e) {
      debugPrint('ホテル取得エラー: $e');
    }
    return {
      'price': 7040,
      'name': '宿泊施設 (デフォルト)',
      'link': 'https://www.google.com/travel/hotels',
    };
  }

  // ーーー 🧮 4. 旅費最小化 計算ロジック ーーー
  void calculateCheapestRoute() async {
    setState(() {
      isSearching = true;
      errorMessage = '';
      bestRoute = null;
    });

    try {
      final results = await Future.wait([
        fetchTrainFares(departure),
        fetchFlightFares(destination),
        fetchHotelFare(destination),
      ]);

      final train = results[0];
      final flight = results[1];
      final hotel = results[2];

      // ★ 人数を掛け合わせた交通費総額（電車往復＋飛行機往復分 × 人数）
      int travelCostNgo =
          (train['NGO']! + (flight['NGO']!['price'] as int)) * travelerCount;
      int travelCostKix =
          (train['KIX']! + (flight['KIX']!['price'] as int)) * travelerCount;

      // ホテル代（※一般的にホテルの最低価格表示は1部屋あたりのことが多いですが、1人あたりの場合は人数をかけるなど調整可能です。ここではシンプルにホテル代＋交通費×人数として計算）
      int totalCentrair = travelCostNgo + (hotel['price'] as int);
      int totalKansai = travelCostKix + (hotel['price'] as int);

      setState(() {
        isSearching = false;
        if (totalCentrair <= totalKansai) {
          bestRoute = {
            'title': '中部国際空港（セントレア）経由ルート',
            'total': totalCentrair,
            'train': train['NGO']! * travelerCount,
            'flight': {
              'price': (flight['NGO']!['price'] as int) * travelerCount,
              'unitPrice': flight['NGO']!['price'],
              'name': flight['NGO']!['name'],
              'link': flight['NGO']!['link'],
            },
            'hotel': hotel,
            'travelerCount': travelerCount,
          };
        } else {
          bestRoute = {
            'title': '関西国際空港（関空）経由ルート',
            'total': totalKansai,
            'train': train['KIX']! * travelerCount,
            'flight': {
              'price': (flight['KIX']!['price'] as int) * travelerCount,
              'unitPrice': flight['KIX']!['price'],
              'name': flight['KIX']!['name'],
              'link': flight['KIX']!['link'],
            },
            'hotel': hotel,
            'travelerCount': travelerCount,
          };
        }
      });
    } catch (e) {
      setState(() {
        isSearching = false;
        errorMessage = 'エラー詳細: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('最安旅費ナビ PRO'),
        backgroundColor: Colors.teal.shade100,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: departure,
                            decoration: const InputDecoration(
                              labelText: '出発地',
                              prefixIcon: Icon(Icons.train),
                            ),
                            onChanged: (val) => departure = val,
                          ),
                        ),
                        const Icon(Icons.swap_horiz, color: Colors.grey),
                        Expanded(
                          child: TextFormField(
                            initialValue: destination,
                            decoration: const InputDecoration(
                              labelText: '目的地',
                              prefixIcon: Icon(Icons.flight_land),
                            ),
                            onChanged: (val) => destination = val,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: startDate,
                            decoration: const InputDecoration(
                              labelText: '出発日（年-月-日）',
                              prefixIcon: Icon(Icons.calendar_today),
                            ),
                            onChanged: (val) => startDate = val,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            initialValue: endDate,
                            decoration: const InputDecoration(
                              labelText: '帰着日（年-月-日）',
                              prefixIcon: Icon(Icons.event),
                            ),
                            onChanged: (val) => endDate = val,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ★ 人数選択用のドロップダウン
                    Row(
                      children: [
                        const Icon(Icons.group, color: Colors.grey),
                        const SizedBox(width: 12),
                        const Text(
                          '旅行人数（大人）: ',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<int>(
                          value: travelerCount,
                          items: [1, 2, 3, 4, 5, 6].map((int value) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value 人'),
                            );
                          }).toList(),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              setState(() {
                                travelerCount = newValue;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: calculateCheapestRoute,
                      icon: const Icon(Icons.bolt, color: Colors.amber),
                      label: const Text(
                        '最安値をリアルタイム検索',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (isSearching)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('リアルタイム最適化ルートを計算中...'),
                  ],
                ),
              )
            else if (errorMessage.isNotEmpty)
              Center(
                child: Text(
                  errorMessage,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else if (bestRoute != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Card(
                    color: Colors.amber.shade50,
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Colors.amber, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.monetization_on,
                                color: Colors.amber,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'LIVE 最安コスト最適化結果（${bestRoute!['travelerCount']}人分）',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Text(
                            bestRoute!['title'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '総額（ホテル＋全交通費）： ¥${bestRoute!['total']}',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            '📋 リアルタイム内訳（タップして詳細ページへ）',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '・1. 地上移動費（$departure〜各空港往復 × ${bestRoute!['travelerCount']}人）: ¥${bestRoute!['train']}',
                          ),
                          const SizedBox(height: 8),
                          // ✈️ 航空会社名（人数分×単価）
                          InkWell(
                            onTap: () =>
                                _launchURL(bestRoute!['flight']['link']),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Row(
                                children: [
                                  const Text('・2. 航空券: '),
                                  Expanded(
                                    child: Text(
                                      '${bestRoute!['flight']['name']} (1人¥${bestRoute!['flight']['unitPrice']} × ${bestRoute!['travelerCount']}人 = ¥${bestRoute!['flight']['price']})',
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.open_in_new,
                                    size: 16,
                                    color: Colors.blue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 🏨 ホテル名
                          InkWell(
                            onTap: () =>
                                _launchURL(bestRoute!['hotel']['link']),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Row(
                                children: [
                                  const Text('・3. 宿泊: '),
                                  Expanded(
                                    child: Text(
                                      '${bestRoute!['hotel']['name']} (¥${bestRoute!['hotel']['price']})',
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.open_in_new,
                                    size: 16,
                                    color: Colors.blue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              const Center(child: Text('条件を入力して、最適化ボタンを押してください。')),
          ],
        ),
      ),
    );
  }
}
