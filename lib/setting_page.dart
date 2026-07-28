import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'installation_identity.dart';
import 'nickname_generator.dart';
import 'admin_page.dart';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;
const _appMutedGreen = Color(0xFF81A684);

// 마이페이지 화면
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _QuoteRequestPage extends StatefulWidget {
  const _QuoteRequestPage({required this.deviceId, required this.displayName});

  final String? deviceId;
  final String displayName;

  @override
  State<_QuoteRequestPage> createState() => _QuoteRequestPageState();
}

class _QuoteRequestPageState extends State<_QuoteRequestPage> {
  static const _fieldBackground = Color(0xFFFAFAFA);
  static const _fieldBorder = Color(0xFFE0E0E0);
  static const _hintColor = Color(0xFFA3A3A3);
  static const _submitBlue = Color(0xFF538CD2);

  final TextEditingController _quoteController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _categoryFieldKey = GlobalKey();
  final GlobalKey _authorFieldKey = GlobalKey();
  final GlobalKey _quoteFieldKey = GlobalKey();

  List<String> _categories = <String>[];
  String? _selectedCategory;
  String? _categoryError;
  String? _authorError;
  String? _quoteError;
  String? _submitError;
  XFile? _selectedImage;
  Uint8List? _imagePreviewBytes;
  bool _isLoadingCategories = true;
  bool _isSubmitting = false;
  bool _isSubmitted = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _quoteController.dispose();
    _authorController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final result = await supabase
          .from('quotes')
          .select('tag_kr')
          .not('tag_kr', 'is', null);
      final seen = <String>{};
      for (final row in result as List) {
        final tag = row['tag_kr']?.toString().trim();
        if (tag != null && tag.isNotEmpty) seen.add(tag);
      }
      if (!mounted) return;
      setState(() {
        _categories = seen.toList()..sort();
        _isLoadingCategories = false;
      });
    } catch (error) {
      debugPrint('카테고리 로드 실패: $error');
      if (!mounted) return;
      setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _pickAuthorImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: image.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      maxWidth: 1080,
      maxHeight: 1080,
      compressQuality: 80,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '사진 영역 설정',
          toolbarColor: Colors.white,
          toolbarWidgetColor: Colors.black87,
          activeControlsWidgetColor: _appMutedGreen,
          backgroundColor: Colors.black,
          cropStyle: CropStyle.circle,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          hideBottomControls: true,
          showCropGrid: false,
        ),
        IOSUiSettings(
          title: '사진 영역 설정',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          rotateButtonsHidden: true,
          rotateClockwiseButtonHidden: true,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );

    if (croppedFile == null) return;
    final bytes = await File(croppedFile.path).readAsBytes();
    if (!mounted) return;
    setState(() {
      _selectedImage = XFile(croppedFile.path);
      _imagePreviewBytes = bytes;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final categoryMissing = _selectedCategory == null;
    final authorMissing = _authorController.text.trim().isEmpty;
    final quoteMissing = _quoteController.text.trim().isEmpty;

    setState(() {
      _categoryError = categoryMissing ? '카테고리를 선택해 주세요.' : null;
      _authorError = authorMissing ? '저자를 입력해 주세요.' : null;
      _quoteError = quoteMissing ? '명언 내용을 입력해 주세요.' : null;
      _submitError = null;
    });

    final firstInvalidKey = categoryMissing
        ? _categoryFieldKey
        : authorMissing
        ? _authorFieldKey
        : quoteMissing
        ? _quoteFieldKey
        : null;
    if (firstInvalidKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToField(firstInvalidKey);
      });
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final insertResult = await supabase
          .from('request_quotes')
          .insert({
            'text_kr': _quoteController.text.trim(),
            'resoner_kr': _authorController.text.trim(),
            'tag_kr': _selectedCategory,
            'device_id': widget.deviceId,
          })
          .select('id')
          .single();

      final requestQuoteId = insertResult['id'];
      if (_selectedImage != null) {
        try {
          final bytes = await File(_selectedImage!.path).readAsBytes();
          final fileExt = _selectedImage!.path.split('.').last;
          final filePath =
              'quote_requests/${InstallationIdentity.id}/$requestQuoteId.$fileExt';

          await supabase.storage
              .from('avatars')
              .uploadBinary(
                filePath,
                bytes,
                fileOptions: FileOptions(
                  upsert: true,
                  contentType: 'image/$fileExt',
                ),
              );
          final imageUrl = supabase.storage
              .from('avatars')
              .getPublicUrl(filePath);
          await supabase.from('request_quote_images').insert({
            'request_quote_idx': requestQuoteId,
            'image_url': imageUrl,
          });
        } catch (error) {
          debugPrint('이미지 업로드 실패 (신청은 완료됨): $error');
        }
      }

      if (!mounted) return;
      setState(() => _isSubmitted = true);
    } catch (error) {
      if (!mounted) return;
      debugPrint('명언 신청 실패: $error');
      setState(() {
        _submitError = '신청을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
      });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _scrollToField(GlobalKey fieldKey) async {
    final fieldContext = fieldKey.currentContext;
    if (!mounted || fieldContext == null) return;
    await Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.18,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSubmitted) return _buildSuccessPage();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '명언 신청',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 188,
                child: ClipRect(
                  child: Image.asset(
                    'assets/quotes_illust.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              _buildIntroduction(),
              const SizedBox(height: 124),
              _buildLabel('명언 카테고리', '필수'),
              const SizedBox(height: 14),
              Container(key: _categoryFieldKey, child: _buildCategoryField()),
              const SizedBox(height: 44),
              _buildLabel('저자', '필수'),
              const SizedBox(height: 14),
              Column(
                key: _authorFieldKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 47,
                    child: TextField(
                      controller: _authorController,
                      maxLength: 50,
                      style: const TextStyle(fontSize: 17),
                      onChanged: (value) {
                        if (_authorError != null && value.trim().isNotEmpty) {
                          setState(() => _authorError = null);
                        }
                      },
                      decoration: _inputDecoration(
                        hintText: '저자를 입력해 주세요.',
                        hasError: _authorError != null,
                      ).copyWith(counterText: ''),
                    ),
                  ),
                  if (_authorError != null) _buildFieldError(_authorError!),
                ],
              ),
              const SizedBox(height: 44),
              _buildLabel('명언 내용', '필수'),
              const SizedBox(height: 14),
              Column(
                key: _quoteFieldKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 169,
                    child: TextField(
                      controller: _quoteController,
                      maxLines: null,
                      expands: true,
                      maxLength: 300,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontSize: 17, height: 1.45),
                      onChanged: (value) {
                        if (_quoteError != null && value.trim().isNotEmpty) {
                          setState(() => _quoteError = null);
                        }
                      },
                      decoration: _inputDecoration(
                        hintText: '명언 내용을 입력해 주세요.',
                        hasError: _quoteError != null,
                        contentPadding: const EdgeInsets.fromLTRB(
                          20,
                          17,
                          20,
                          17,
                        ),
                      ).copyWith(counterText: ''),
                    ),
                  ),
                  if (_quoteError != null) _buildFieldError(_quoteError!),
                ],
              ),
              const SizedBox(height: 44),
              _buildLabel('저자 사진', '선택'),
              const SizedBox(height: 14),
              _buildImagePicker(),
              const SizedBox(height: 48),
              if (_submitError != null) ...[
                _buildSubmitError(_submitError!),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 53,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _submitBlue,
                    disabledBackgroundColor: _submitBlue.withValues(
                      alpha: 0.55,
                    ),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.note_add_outlined, size: 24),
                  label: Text(
                    _isSubmitting ? '신청 중...' : '명언 신청하기',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroduction() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Text.rich(
            textAlign: TextAlign.center,
            TextSpan(
              style: const TextStyle(fontSize: 17, height: 1.5),
              children: [
                TextSpan(
                  text: widget.displayName,
                  style: const TextStyle(
                    color: _appMutedGreen,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const TextSpan(
                  text: '님,\n',
                  style: TextStyle(color: Color(0xFF3B3B3B)),
                ),
                const TextSpan(
                  text: '힐링 하이를 많은 분들과 함께해 주셔서 감사해요!',
                  style: TextStyle(color: Color(0xFF3B3B3B)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '여러분만의 따뜻한 말,\n누군가에게 위로가 되었던 한마디가 있으신가요?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '아래에 내용을 남겨주시면\n힐링 하이에서 소개될 수 있도록 소중히 살펴볼게요.\n\n'
            '여러분의 따뜻한 마음을 기다릴게요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF3B3B3B),
              fontSize: 17,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String title, String requirement) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$title ',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 19,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: '($requirement)',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    bool hasError = false,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 12,
    ),
  }) {
    final borderColor = hasError ? Colors.red : _fieldBorder;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: borderColor),
    );
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: _hintColor, fontSize: 17),
      filled: true,
      fillColor: _fieldBackground,
      contentPadding: contentPadding,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: hasError ? Colors.red : _submitBlue,
          width: 1.4,
        ),
      ),
    );
  }

  Widget _buildCategoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 47,
          padding: const EdgeInsets.only(left: 20, right: 16),
          decoration: BoxDecoration(
            color: _fieldBackground,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _categoryError == null ? _fieldBorder : Colors.red,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedCategory,
              isExpanded: true,
              icon: const Icon(
                Icons.arrow_drop_down,
                size: 22,
                color: Color(0xFF777777),
              ),
              hint: Text(
                _isLoadingCategories ? '카테고리 로딩 중...' : '카테고리를 선택해 주세요.',
                style: const TextStyle(color: _hintColor, fontSize: 17),
              ),
              items: _categories
                  .map(
                    (tag) => DropdownMenuItem<String>(
                      value: tag,
                      child: Text(tag, style: const TextStyle(fontSize: 17)),
                    ),
                  )
                  .toList(),
              onChanged: _isLoadingCategories
                  ? null
                  : (value) {
                      setState(() {
                        _selectedCategory = value;
                        if (value != null) _categoryError = null;
                      });
                    },
            ),
          ),
        ),
        if (_categoryError != null) _buildFieldError(_categoryError!),
      ],
    );
  }

  Widget _buildFieldError(String message) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.error_outline, color: Colors.red, size: 16),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitError(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFC9C9)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _submitError = null),
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.close, color: Color(0xFFB42318), size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: _pickAuthorImage,
      child: Container(
        width: double.infinity,
        height: 169,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _fieldBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _fieldBorder),
        ),
        child: _imagePreviewBytes == null
            ? const Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 42,
                  color: Color(0xFF777777),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(_imagePreviewBytes!, fit: BoxFit.cover),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedImage = null;
                          _imagePreviewBytes = null;
                        });
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSuccessPage() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: _appMutedGreen,
                  size: 68,
                ),
                const SizedBox(height: 18),
                const Text(
                  '신청이 완료되었습니다!',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '관리자 검토 후 등록됩니다.',
                  style: TextStyle(color: Color(0xFF777777), fontSize: 15),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 53,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _submitBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MyPageScreenState extends State<MyPageScreen> {
  final TextEditingController _nameController = TextEditingController();

  // 사용자 데이터
  String _profileImageUrl = '';
  String _name = '';
  String _selectedLanguage = 'kor'; // 기본값: 한국어
  int _shareCount = 0;
  String? _deviceId;
  bool _isLoading = true;
  bool _nicknameSaved = false; // 닉네임 저장 성공 상태
  int _adminTapCount = 0;

  String _withCacheBuster(String imageUrl) {
    final separator = imageUrl.contains('?') ? '&' : '?';
    return '$imageUrl${separator}v=${DateTime.now().microsecondsSinceEpoch}';
  }

  // 공유 등급 계산
  String get _shareLevel {
    if (_shareCount >= 100) return '골드 / $_shareCount개';
    if (_shareCount >= 10) return '실버 / $_shareCount개';
    if (_shareCount >= 1) return '브론즈 / $_shareCount개';
    return '없음 / 0개';
  }

  int get _shareTierTarget {
    if (_shareCount >= 100) return 100;
    if (_shareCount >= 10) return 100;
    if (_shareCount >= 1) return 10;
    return 1;
  }

  int get _shareProgress {
    final target = _shareTierTarget;
    return ((_shareCount / target) * 100).clamp(0, 100).toInt();
  }

  bool get _hasChangedProfileImage => _profileImageUrl.trim().isNotEmpty;

  bool get _hasChangedName {
    final deviceId = _deviceId;
    final savedName = _name.trim();
    if (deviceId == null || savedName.isEmpty) return false;
    return savedName != generateNickname(deviceId);
  }

  // 언어 옵션
  final Map<String, String> _languageOptions = {'kor': '한국어', 'eng': '영어'};

  @override
  void initState() {
    super.initState();
    _getDeviceId();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // 디바이스 고유 ID 가져오기
  Future<void> _getDeviceId() async {
    try {
      final deviceId = InstallationIdentity.id;

      setState(() {
        _deviceId = deviceId;
      });

      await _loadUserData();
    } catch (e) {
      print('디바이스 ID 가져오기 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Supabase에서 사용자 정보 불러오기
  Future<void> _loadUserData() async {
    if (_deviceId == null) return;

    try {
      // 공유 카운트 로드 (device_id 기반 - users 행 없이도 동작)
      final shareData = await supabase
          .from('device_shares')
          .select('share_count')
          .eq('device_id', _deviceId!)
          .maybeSingle();

      final shareCount = shareData != null
          ? (shareData['share_count'] ?? 0) as int
          : 0;

      final response = await supabase
          .from('users')
          .select()
          .eq('device_id', _deviceId!)
          .maybeSingle();

      if (response != null) {
        // 데이터가 있으면 불러오기
        setState(() {
          _name = response['user_id'] ?? '';
          _profileImageUrl = response['profile_image_url'] ?? '';
          _selectedLanguage = response['language'] ?? 'kor';
          _shareCount = shareCount;
          _nameController.text = _name;
          _isLoading = false;
        });
      } else {
        // 데이터가 없으면 랜덤 닉네임 표시
        setState(() {
          _nameController.text = '';
          _selectedLanguage = 'kor';
          _shareCount = shareCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('사용자 정보 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 언어 변경 및 저장
  Future<void> _updateLanguage(String languageCode) async {
    if (_deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
      );
      return;
    }

    try {
      // Supabase에 언어 업데이트
      await supabase.from('users').upsert({
        'device_id': _deviceId,
        'user_id': _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : _name,
        'language': languageCode,
        'profile_image_url': _profileImageUrl.isNotEmpty
            ? _profileImageUrl
            : null,
      }, onConflict: 'device_id').select();

      setState(() {
        _selectedLanguage = languageCode;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('언어가 ${_languageOptions[languageCode]}(으)로 변경되었습니다'),
            backgroundColor: _appMutedGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('언어 변경 실패: $e')));
      }
      print('언어 업데이트 오류: $e');
    }
  }

  // 이미지 선택 및 업로드
  Future<void> _pickAndUploadImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image == null) return;

      // 이미지 크롭 (원형 프로필 스타일)
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        maxWidth: 512,
        maxHeight: 512,
        compressQuality: 75,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '프로필 사진',
            toolbarColor: Colors.white,
            statusBarColor: Colors.white,
            toolbarWidgetColor: Colors.black87,
            activeControlsWidgetColor: _appMutedGreen,
            backgroundColor: Colors.black,
            cropStyle: CropStyle.circle,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: true,
            showCropGrid: false,
          ),
          IOSUiSettings(
            title: '프로필 사진',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            rotateButtonsHidden: true,
            rotateClockwiseButtonHidden: true,
            aspectRatioPickerButtonHidden: true,
          ),
        ],
      );

      if (croppedFile == null) return;

      if (_deviceId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
          );
        }
        return;
      }

      // 로딩 표시
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이미지 업로드 중...')));
      }

      // 파일 읽기
      final bytes = await File(croppedFile.path).readAsBytes();
      final fileExt = croppedFile.path.split('.').last;
      final fileName = '$_deviceId.$fileExt';
      final filePath = 'profiles/$fileName';

      // Supabase Storage에 업로드
      await supabase.storage
          .from('avatars')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/$fileExt',
            ),
          );

      // Public URL 가져오기
      final imageUrl = supabase.storage.from('avatars').getPublicUrl(filePath);
      final refreshedImageUrl = _withCacheBuster(imageUrl);

      // users 테이블 업데이트 (device_id를 기준으로 upsert)
      await supabase.from('users').upsert({
        'device_id': _deviceId,
        'user_id': _nameController.text.trim(),
        'profile_image_url': refreshedImageUrl,
        'language': _selectedLanguage,
      }, onConflict: 'device_id').select();

      // 기존 캐시 제거 후 새 이미지 반영
      if (_profileImageUrl.isNotEmpty) {
        await NetworkImage(_profileImageUrl).evict();
      }

      if (!mounted) return;

      setState(() {
        _profileImageUrl = refreshedImageUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('프로필 사진이 업데이트되었습니다!'),
            backgroundColor: _appMutedGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('이미지 업로드 실패: $e')));
      }
      print('이미지 업로드 오류: $e');
    }
  }

  // Supabase에 사용자 정보 저장
  Future<void> _saveUserToSupabase() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ID 또는 이름을 입력해주세요')));
      return;
    }

    if (_deviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
      );
      return;
    }

    try {
      final newName = _nameController.text.trim();

      // 닉네임 중복 확인 (자신의 device_id 제외)
      final isAvailable = await supabase.rpc(
        'is_nickname_available',
        params: {'p_user_id': newName},
      );

      if (isAvailable != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('중복된 ID 또는 이름입니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Supabase users 테이블에 데이터 저장
      await supabase.from('users').upsert({
        'device_id': _deviceId,
        'user_id': newName,
        'profile_image_url': _profileImageUrl.isNotEmpty
            ? _profileImageUrl
            : null,
        'language': _selectedLanguage,
      }, onConflict: 'device_id').select();

      setState(() {
        _name = newName;
        _nicknameSaved = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ID 또는 이름이 저장되었습니다.'),
            backgroundColor: _appMutedGreen,
          ),
        );
      }

      // 2초 후 체크박스를 다시 회색으로
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _nicknameSaved = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
      print('Supabase 저장 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 로딩 중일 때
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F5F5),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                // 상단 제목
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _adminTapCount++;
                    if (_adminTapCount >= 5) {
                      _adminTapCount = 0;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AdminPage()),
                      );
                    }
                  },
                  child: const Row(
                    children: [
                      Text(
                        '프로필 설정',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // 프로필 이미지와 월계관
                GestureDetector(
                  onTap: _pickAndUploadImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 2,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // 프로필 이미지
                        Positioned.fill(
                          child: ClipOval(
                            child: _profileImageUrl.isNotEmpty
                                ? Image.network(
                                    _profileImageUrl,
                                    key: ValueKey(_profileImageUrl),
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.person,
                                      size: 60,
                                      color: Colors.grey,
                                    ),
                                  ),
                          ),
                        ),
                        // 카메라 아이콘 (편집 힌트)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                        // 월계관 장식 이미지 사용 대신 아이콘만 표시
                        // const Positioned(
                        //   top: -10,
                        //   left: -10,
                        //   right: -10,
                        //   child: SizedBox(
                        //     height: 40,
                        //     child: Icon(
                        //       Icons.emoji_events,
                        //       color: Colors.amber,
                        //       size: 30,
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                ),
                if (!_hasChangedProfileImage) ...[
                  const SizedBox(height: 10),
                  const Text(
                    '공유 10회 완료 후 프로필 사진 설정 가능',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFE58B8B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                ] else
                  const SizedBox(height: 40),

                // 이름 입력 필드 (공유 1회 이상이면 편집 가능)
                if (_shareCount >= 1)
                  _buildInputField(
                    label: 'ID 또는 이름',
                    controller: _nameController,
                    hintText: 'ID 또는 이름을 입력하세요',
                    hasCheckIcon: true,
                  )
                else
                  _buildReadOnlyNameField(
                    label: 'ID 또는 이름',
                    value: _deviceId != null
                        ? generateNickname(_deviceId!)
                        : '로딩중...',
                  ),
                if (!_hasChangedName) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '공유 1회 완료 후 이름 설정 가능',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFE58B8B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // 언어 선택 필드
                // _buildLanguageSelector(),
                // const SizedBox(height: 30),

                // 공유 등급/개 섹션
                _buildInfoSection(
                  title: '공유 등급/개',
                  value: _shareLevel,
                  valueColor: Colors.red,
                  onSearchTap: _showShareLeaderboard,
                ),
                const SizedBox(height: 20),

                // 공유 달성도 섹션
                _buildAchievementSection(),

                // 명언 신청 버튼 (공유 5회 이상 시 표시)
                if (_shareCount >= 5) ...[
                  const SizedBox(height: 30),
                  _buildQuoteRequestButton(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '언어',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 56, // 다른 입력 필드와 동일한 높이
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: ButtonTheme(
              alignedDropdown: true,
              child: DropdownButton<String>(
                value: _selectedLanguage,
                isExpanded: true,
                borderRadius: BorderRadius.circular(25),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                icon: const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.arrow_drop_down, color: Colors.grey),
                ),
                items: _languageOptions.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(entry.value),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null && newValue != _selectedLanguage) {
                    _updateLanguage(newValue);
                  }
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    required bool hasCheckIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            enableInteractiveSelection: true,
            onTap: () {
              SystemChannels.textInput.invokeMethod('TextInput.show');
            },
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              suffixIcon: hasCheckIcon
                  ? GestureDetector(
                      onTap: _saveUserToSupabase,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                        margin: const EdgeInsets.all(8),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: _nicknameSaved
                              ? _appMutedGreen
                              : Colors.grey[400],
                          shape: BoxShape.circle,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return ScaleTransition(
                              scale: animation,
                              child: child,
                            );
                          },
                          child: Icon(
                            Icons.check,
                            key: ValueKey<bool>(_nicknameSaved),
                            color: Colors.white,
                            size: _nicknameSaved ? 20 : 16,
                          ),
                        ),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyNameField({
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            '명언을 1회 이상 공유하면 ID 또는 이름을 설정할 수 있어요!',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _loadShareLeaderboard() async {
    final response = await supabase.rpc('get_share_leaderboard');
    final rows = List<Map<String, dynamic>>.from(response as List);

    return rows.map((row) {
      final count = row['share_count'];
      final rank = row['rank'];
      return <String, dynamic>{
        'name': row['display_name']?.toString() ?? '익명',
        'shareCount': count is int
            ? count
            : int.tryParse(count?.toString() ?? '') ?? 0,
        'isCurrentUser': row['is_current_user'] == true,
        'rank': rank is int ? rank : int.tryParse(rank?.toString() ?? '') ?? 0,
      };
    }).toList();
  }

  Future<void> _showShareLeaderboard() async {
    final leaderboardFuture = _loadShareLeaderboard();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.8,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF5F5F5),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(Icons.leaderboard_outlined, color: _appMutedGreen),
                  SizedBox(width: 8),
                  Text(
                    '공유 리더보드',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: leaderboardFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Center(
                        child: Text(
                          '리더보드를 불러오지 못했습니다.\n잠시 후 다시 시도해주세요.',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    final entries = snapshot.data ?? [];
                    Map<String, dynamic>? currentEntry;
                    for (final entry in entries) {
                      if (entry['isCurrentUser'] == true) {
                        currentEntry = entry;
                        break;
                      }
                    }

                    return Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: _appMutedGreen.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                '내 순위',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text(
                                currentEntry == null
                                    ? '-'
                                    : '${currentEntry['rank']}위 · ${currentEntry['shareCount']}회',
                                style: const TextStyle(
                                  color: _appMutedGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: entries.isEmpty
                              ? const Center(child: Text('표시할 사용자가 없습니다.'))
                              : ListView.separated(
                                  itemCount: entries.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final entry = entries[index];
                                    final isCurrentUser =
                                        entry['isCurrentUser'] as bool;
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: isCurrentUser
                                            ? _appMutedGreen.withValues(
                                                alpha: 0.1,
                                              )
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: ListTile(
                                        leading: SizedBox(
                                          width: 34,
                                          child: Center(
                                            child: Text(
                                              '${entry['rank']}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: index < 3
                                                    ? _appMutedGreen
                                                    : Colors.grey[600],
                                              ),
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          '${entry['name']}${isCurrentUser ? ' (나)' : ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: isCurrentUser
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                          ),
                                        ),
                                        trailing: Text(
                                          '${entry['shareCount']}회',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required String value,
    Color? valueColor,
    VoidCallback? onSearchTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            if (onSearchTap != null) ...[
              const SizedBox(width: 4),
              IconButton(
                onPressed: onSearchTap,
                tooltip: '공유 리더보드 보기',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.search, size: 19, color: Colors.grey),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuoteRequestButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () {
          final fallbackName = _deviceId != null
              ? generateNickname(_deviceId!)
              : '';
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _QuoteRequestPage(
                deviceId: _deviceId,
                displayName: _name.isNotEmpty ? _name : fallbackName,
              ),
            ),
          );
        },
        icon: const Icon(Icons.edit_note, size: 22),
        label: const Text(
          '명언 신청',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _appMutedGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  // 이전 하단 시트 구현은 기존 데이터 흐름 참고용으로 유지한다.
  // ignore: unused_element
  Future<void> _showQuoteRequestForm() async {
    final quoteController = TextEditingController();
    final authorController = TextEditingController();
    bool isSubmitted = false;
    String? selectedCategory;
    List<String> categories = [];
    XFile? selectedImage;
    Uint8List? imagePreviewBytes;

    // Supabase에서 카테고리 목록 가져오기
    try {
      final result = await supabase
          .from('quotes')
          .select('tag_kr')
          .not('tag_kr', 'is', null);
      final Set<String> seen = {};
      for (final row in result as List) {
        final tag = row['tag_kr']?.toString();
        if (tag != null && tag.isNotEmpty) seen.add(tag);
      }
      categories = seen.toList()..sort();
    } catch (e) {
      print('카테고리 로드 실패: $e');
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (isSubmitted) {
              return Container(
                padding: const EdgeInsets.all(32),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: _appMutedGreen,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '신청이 완료되었습니다!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '관리자 검토 후 등록됩니다.',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _appMutedGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text('확인'),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 핸들바
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // 안내 문구와 입력 폼을 초기 화면보다 약 30% 아래에서 시작한다.
                      SizedBox(height: MediaQuery.sizeOf(context).height * 0.3),

                      // 제목
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            Text.rich(
                              textAlign: TextAlign.center,
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: _name.isNotEmpty
                                        ? _name
                                        : (_deviceId != null
                                              ? generateNickname(_deviceId!)
                                              : ''),
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _appMutedGreen,
                                    ),
                                  ),
                                  const TextSpan(
                                    text: '님,',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '힐링 하이를 많은 분들과 함께해 주셔서 감사해요!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              '여러분만의 따뜻한 말,\n누군가에게 위로가 되었던 한마디가 있으신가요?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '아래에 내용을 남겨주시면\n힐링 하이에서 소개될 수 있도록 소중히 살펴볼게요.\n\n'
                              '여러분의 따뜻한 마음을 기다릴게요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[500],
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 명언 내용 입력
                      const Text(
                        '명언 내용 *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: quoteController,
                        maxLines: 4,
                        maxLength: 300,
                        decoration: InputDecoration(
                          hintText: '명언을 입력해주세요',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: _appMutedGreen),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 저자 입력
                      const Text(
                        '저자 *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: authorController,
                        maxLength: 50,
                        decoration: InputDecoration(
                          hintText: '저자를 입력해주세요',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: _appMutedGreen),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 카테고리 선택
                      const Text(
                        '카테고리 *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedCategory,
                            isExpanded: true,
                            hint: Text(
                              categories.isEmpty
                                  ? '카테고리 로딩 중...'
                                  : '카테고리를 선택해주세요',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                            items: categories.map((tag) {
                              return DropdownMenuItem<String>(
                                value: tag,
                                child: Text(
                                  tag,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setModalState(() {
                                selectedCategory = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 사진 첨부 (선택)
                      const Text(
                        '사진 첨부 (선택)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (image == null) return;

                          final croppedFile = await ImageCropper().cropImage(
                            sourcePath: image.path,
                            aspectRatio: const CropAspectRatio(
                              ratioX: 1,
                              ratioY: 1,
                            ),
                            maxWidth: 1080,
                            maxHeight: 1080,
                            compressQuality: 80,
                            uiSettings: [
                              AndroidUiSettings(
                                toolbarTitle: '사진 영역 설정',
                                toolbarColor: Colors.white,
                                statusBarColor: Colors.white,
                                toolbarWidgetColor: Colors.black87,
                                activeControlsWidgetColor: _appMutedGreen,
                                backgroundColor: Colors.black,
                                cropStyle: CropStyle.circle,
                                initAspectRatio: CropAspectRatioPreset.square,
                                lockAspectRatio: true,
                                hideBottomControls: true,
                                showCropGrid: false,
                              ),
                              IOSUiSettings(
                                title: '사진 영역 설정',
                                aspectRatioLockEnabled: true,
                                resetAspectRatioEnabled: false,
                                rotateButtonsHidden: true,
                                rotateClockwiseButtonHidden: true,
                                aspectRatioPickerButtonHidden: true,
                              ),
                            ],
                          );

                          if (croppedFile == null) return;
                          final bytes = await File(
                            croppedFile.path,
                          ).readAsBytes();
                          setModalState(() {
                            selectedImage = XFile(croppedFile.path);
                            imagePreviewBytes = bytes;
                          });
                        },
                        child: Container(
                          width: double.infinity,
                          height: imagePreviewBytes != null ? null : 120,
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: imagePreviewBytes != null
                              ? Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.memory(
                                        imagePreviewBytes!,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: GestureDetector(
                                        onTap: () {
                                          setModalState(() {
                                            selectedImage = null;
                                            imagePreviewBytes = null;
                                          });
                                        },
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 36,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '사진 선택',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 신청 버튼
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (quoteController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('명언 내용을 입력해주세요'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            if (authorController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('저자를 입력해주세요'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            if (selectedCategory == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('카테고리를 선택해주세요'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            try {
                              final insertResult = await supabase
                                  .from('request_quotes')
                                  .insert({
                                    'text_kr': quoteController.text.trim(),
                                    'resoner_kr': authorController.text.trim(),
                                    'tag_kr': selectedCategory,
                                    'device_id': _deviceId,
                                  })
                                  .select('id')
                                  .single();

                              final requestQuoteId = insertResult['id'];

                              if (selectedImage != null) {
                                try {
                                  final bytes = await File(
                                    selectedImage!.path,
                                  ).readAsBytes();
                                  final fileExt = selectedImage!.path
                                      .split('.')
                                      .last;
                                  final filePath =
                                      'quote_requests/${InstallationIdentity.id}/$requestQuoteId.$fileExt';

                                  await supabase.storage
                                      .from('avatars')
                                      .uploadBinary(
                                        filePath,
                                        bytes,
                                        fileOptions: FileOptions(
                                          upsert: true,
                                          contentType: 'image/$fileExt',
                                        ),
                                      );

                                  final imageUrl = supabase.storage
                                      .from('avatars')
                                      .getPublicUrl(filePath);

                                  await supabase
                                      .from('request_quote_images')
                                      .insert({
                                        'request_quote_idx': requestQuoteId,
                                        'image_url': imageUrl,
                                      });
                                } catch (imgErr) {
                                  print('이미지 업로드 실패 (신청은 완료됨): $imgErr');
                                }
                              }

                              setModalState(() {
                                isSubmitted = true;
                              });
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('신청 실패: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _appMutedGreen,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            '신청하기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAchievementInfoDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('공유 달성도 안내'),
        content: const Text(
          '공유 달성도의 게이지가 채워지면 추가하고 싶은 문구를 제작자에게 보낼 수 있어요.\n\n'
          '여러분의 말이나 원하는 저자의 명언을 자유롭게 추가해보세요.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '공유 달성도',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _showAchievementInfoDialog,
              child: const Icon(
                Icons.help_outline,
                color: Colors.grey,
                size: 16,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 진행률 표시
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_shareCount/$_shareTierTarget',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '$_shareProgress%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 진행바
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: _shareProgress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _appMutedGreen,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Expanded(flex: 100 - _shareProgress, child: Container()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
