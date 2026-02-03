import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'dart:convert';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;

// 보관함 화면
class BookmarkScreen extends StatefulWidget {
  const BookmarkScreen({super.key});

  @override
  State<BookmarkScreen> createState() => _BookmarkScreenState();
}

class _BookmarkScreenState extends State<BookmarkScreen> {
  final List<Map<String, dynamic>> _savedQuotes = [];
  bool _isLoading = true;
  String? _deviceId;
  int? _userIdx;
  Map<String, String> _resonerImages = {}; // quoteId -> imagePath 매핑

  @override
  void initState() {
    super.initState();
    _loadResonerImages();
    _initUserIdentity();
  }

  // assets/resoner/ 폴더의 이미지 목록 로드
  Future<void> _loadResonerImages() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      final resonerFiles = manifestMap.keys
          .where((path) => path.startsWith('assets/resoner/'))
          .toList();

      final Map<String, String> imageMap = {};
      for (final path in resonerFiles) {
        final fileName = path.split('/').last;
        final idMatch = RegExp(r'^(\d+)_').firstMatch(fileName);
        if (idMatch != null) {
          final id = idMatch.group(1)!;
          imageMap[id] = path;
        }
      }

      if (mounted) {
        setState(() {
          _resonerImages = imageMap;
        });
      }
    } catch (e) {
      print('Resoner 이미지 로드 실패: $e');
    }
  }

  // quoteId로 이미지 경로 가져오기
  String? _getResonerImagePath(String? quoteId) {
    if (quoteId == null) return null;
    return _resonerImages[quoteId];
  }

  Future<void> _initUserIdentity() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String? deviceId;

      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        deviceId = info.id;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        deviceId = info.identifierForVendor;
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        deviceId = info.deviceId;
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        deviceId = info.machineId;
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        deviceId = info.systemGUID;
      }

      _deviceId = deviceId;

      if (deviceId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final user = await supabase
          .from('users')
          .select('idx')
          .eq('device_id', deviceId)
          .maybeSingle();

      if (user != null) {
        _userIdx = _toInt(user['idx']);
      }

      await _loadSavedQuotes();
    } catch (e) {
      print('보관함 사용자 식별자 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSavedQuotes() async {
    final userIdx = _userIdx;
    if (userIdx == null) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용자 정보를 불러올 수 없습니다. 프로필을 먼저 저장해주세요.')),
        );
      }
      return;
    }

    try {
      final userQuotes = await supabase
          .from('users_quotes')
          .select('quotes_id')
          .eq('user_idx', userIdx);

      final quoteIds = userQuotes
          .map<String?>((row) => row['quotes_id']?.toString())
          .where((id) => id != null && id!.isNotEmpty)
          .cast<String>()
          .toList();

      if (quoteIds.isEmpty) {
        setState(() {
          _savedQuotes.clear();
          _isLoading = false;
        });
        return;
      }

      final quotes = await supabase
          .from('quotes')
          .select()
          .inFilter('id', quoteIds);

      setState(() {
        _savedQuotes
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(quotes));
        _isLoading = false;
      });
    } catch (e) {
      print('보관함 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('보관함을 불러오지 못했습니다: $e')));
      }
    }
  }

  Future<void> _removeFromBookmark(String? quoteId) async {
    if (quoteId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('명언 ID를 찾을 수 없습니다.')));
      }
      return;
    }

    try {
      final userIdx = _userIdx;
      if (userIdx == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('사용자 정보를 찾을 수 없습니다.')));
        }
        return;
      }

      await supabase
          .from('users_quotes')
          .delete()
          .eq('user_idx', userIdx)
          .eq('quotes_id', quoteId);

      // 리스트에서 제거
      setState(() {
        _savedQuotes.removeWhere((quote) => quote['id']?.toString() == quoteId);
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('보관함에서 삭제되었습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제 중 오류가 발생했습니다: $e')));
      }
    }
  }

  void _shareContent(String title, String content) async {
    try {
      await Share.share(
        '$title\n\n$content\n\n공유됨 - Healing Hi 앱',
        subject: title,
      );
    } catch (e) {
      await Clipboard.setData(
        ClipboardData(text: '$title\n\n$content\n\n공유됨 - Healing Hi 앱'),
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('내용이 클립보드에 복사되었습니다!')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8E3DF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Text(
                    '보관함',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _savedQuotes.isEmpty
                    ? const Center(
                        child: Text(
                          '보관한 명언이 없습니다.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadSavedQuotes,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(top: 10.0),
                          itemCount: _savedQuotes.length,
                          itemBuilder: (context, index) {
                            final quote = _savedQuotes[index];
                            final quoteId = quote['id']?.toString();
                            return _buildBookmarkCard(
                              '${quote['resoner_kr']}',
                              quote['text_kr'],
                              quoteId,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkCard(String title, String content, String? quoteId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF0EE),
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상단: 프로필 이미지 + 저자명
          Row(
            children: [
              ClipOval(
                child: Container(
                  width: 36,
                  height: 36,
                  color: Colors.grey[300],
                  child: _getResonerImagePath(quoteId) != null
                      ? Image.asset(
                          _getResonerImagePath(quoteId)!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(Icons.person, size: 20, color: Colors.grey[600]);
                          },
                        )
                      : Icon(Icons.person, size: 20, color: Colors.grey[600]),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 명언 텍스트 (왼쪽 정렬)
          Text(
            content,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[800],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          // 버튼 영역 (중앙)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () {
                  _removeFromBookmark(quoteId);
                },
                icon: Image.asset('assets/heart2.png', width: 24, height: 24),
                tooltip: '보관함에서 삭제',
              ),
              IconButton(
                onPressed: () {
                  _shareContent(title, content);
                },
                icon: const Icon(Icons.share),
                iconSize: 20,
                color: Colors.grey[600],
                tooltip: '공유하기',
              ),
            ],
          ),
        ],
      ),
    );
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}
