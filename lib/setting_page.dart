import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:typed_data';
import 'dart:io';
import 'installation_identity.dart';
import 'rank_medal.dart';
import 'nickname_generator.dart';
import 'notification_service.dart';
import 'admin_page.dart';
import 'tutorial.dart';
import 'app_popup.dart';
import 'image_mime.dart';

// Supabase 클라이언트 전역 변수
final supabase = Supabase.instance.client;
const _appMutedGreen = Color(0xFF81A684);
const _quoteRequestShareRequirement = 30;

Future<dynamic> _submitQuoteRequest({
  required String quote,
  required String author,
  required String category,
}) {
  return supabase.rpc(
    'submit_quote_request',
    params: {'p_text_kr': quote, 'p_resoner_kr': author, 'p_tag_kr': category},
  );
}

// 마이페이지 화면
class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key, required this.onInterstitialRequested});

  final VoidCallback onInterstitialRequested;

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

enum _ProfileImageAction { select, delete }

class _QuoteRequestPage extends StatefulWidget {
  const _QuoteRequestPage({
    required this.displayName,
    required this.onInterstitialRequested,
  });

  final String displayName;
  final VoidCallback onInterstitialRequested;

  @override
  State<_QuoteRequestPage> createState() => _QuoteRequestPageState();
}

class _QuoteRequestPageState extends State<_QuoteRequestPage> {
  static const _fieldBackground = Color(0xFFFAFAFA);
  static const _fieldBorder = Color(0xFFE0E0E0);
  static const _hintColor = Color(0xFFA3A3A3);
  static const _submitBlue = Color(0xFF538CD2);
  // Figma: 스크롤 좌우 10 + 필드 좌우 20 → 화면 인셋 30(필드 폭 380)
  static const _fieldPadding = EdgeInsets.symmetric(horizontal: 20);

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
      final requestQuoteId = await _submitQuoteRequest(
        quote: _quoteController.text.trim(),
        author: _authorController.text.trim(),
        category: _selectedCategory!,
      );
      if (_selectedImage != null) {
        try {
          final bytes = await File(_selectedImage!.path).readAsBytes();
          final fileExt = ImageMime.extensionOf(_selectedImage!.path);
          final filePath =
              'quote_requests/${InstallationIdentity.id}/$requestQuoteId.$fileExt';

          await supabase.storage
              .from('avatars')
              .uploadBinary(
                filePath,
                bytes,
                fileOptions: FileOptions(
                  upsert: true,
                  contentType: ImageMime.fromExtension(fileExt),
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
      setState(() => _isSubmitting = false);
      await _showCompletionPopup();
    } catch (error) {
      if (!mounted) return;
      debugPrint('명언 신청 실패: $error');
      final shareRequirementNotMet = error.toString().contains(
        '30 shares are required',
      );
      setState(() {
        _submitError = shareRequirementNotMet
            ? '명언을 신청하려면 공유 30회를 완료해 주세요.'
            : '신청을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.';
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        // Figma Apply Top Text: Settings와 같은 규격(상단 61, 높이 43)
        minimum: const EdgeInsets.only(top: 61),
        child: Column(
          children: [
            const SizedBox(
              height: 43,
              width: double.infinity,
              child: Center(
                child: Text(
                  '힐링 하이에 새로운 문장을 더해보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF595959),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                // Figma Middle: 좌우 10, 상단 8. 제목·필드·일러스트는 개별 패딩으로 맞춘다.
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 28),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 5),
                    // Figma PIC: 360×200, 화면 인셋 40
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: SizedBox(
                        height: 200,
                        child: ClipRect(
                          child: Image.asset(
                            'assets/quotes_illust.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: _buildIntroduction(),
                    ),
                    // Figma: 본문 하단 5 + 섹션 간격 38
                    const SizedBox(height: 43),
                    _buildLabel('명언 카테고리', '필수'),
                    const SizedBox(height: 11),
                    Padding(
                      padding: _fieldPadding,
                      child: Container(
                        key: _categoryFieldKey,
                        child: _buildCategoryField(),
                      ),
                    ),
                    const SizedBox(height: 38),
                    _buildLabel('저자', '필수'),
                    const SizedBox(height: 11),
                    Padding(
                      padding: _fieldPadding,
                      child: Column(
                        key: _authorFieldKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 50,
                            child: TextField(
                              controller: _authorController,
                              maxLength: 50,
                              style: const TextStyle(fontSize: 17),
                              onChanged: (value) {
                                if (_authorError != null &&
                                    value.trim().isNotEmpty) {
                                  setState(() => _authorError = null);
                                }
                              },
                              decoration: _inputDecoration(
                                hintText: '저자를 입력해 주세요.',
                                hasError: _authorError != null,
                              ).copyWith(counterText: ''),
                            ),
                          ),
                          if (_authorError != null)
                            _buildFieldError(_authorError!),
                        ],
                      ),
                    ),
                    const SizedBox(height: 38),
                    _buildLabel('명언 내용', '필수'),
                    const SizedBox(height: 11),
                    Padding(
                      padding: _fieldPadding,
                      child: Column(
                        key: _quoteFieldKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Figma Text Box: 높이 206, 내부 패딩 20
                          SizedBox(
                            height: 206,
                            child: TextField(
                              controller: _quoteController,
                              maxLines: null,
                              expands: true,
                              maxLength: 300,
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(
                                fontSize: 17,
                                height: 1.45,
                              ),
                              onChanged: (value) {
                                if (_quoteError != null &&
                                    value.trim().isNotEmpty) {
                                  setState(() => _quoteError = null);
                                }
                              },
                              decoration: _inputDecoration(
                                hintText: '명언 내용을 입력해 주세요.',
                                hasError: _quoteError != null,
                                contentPadding: const EdgeInsets.all(20),
                              ).copyWith(counterText: ''),
                            ),
                          ),
                          if (_quoteError != null)
                            _buildFieldError(_quoteError!),
                        ],
                      ),
                    ),
                    const SizedBox(height: 38),
                    _buildLabel('저자 사진', '선택'),
                    const SizedBox(height: 11),
                    Padding(padding: _fieldPadding, child: _buildImagePicker()),
                    const SizedBox(height: 38),
                    if (_submitError != null) ...[
                      Padding(
                        padding: _fieldPadding,
                        child: _buildSubmitError(_submitError!),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // Figma Apply 버튼: 높이 52, 화면 인셋 10(폭 420)
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
          ],
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
    // Figma ID Title: 좌우 16(화면 26)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text.rich(
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
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    bool hasError = false,
    // Figma ID: 필드 내부 텍스트 좌우 23
    EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
      horizontal: 23,
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
          height: 50,
          padding: const EdgeInsets.only(left: 23, right: 25),
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
              // Figma Select: 12×8 삼각형 화살표
              icon: const SizedBox(
                width: 12,
                height: 8,
                child: CustomPaint(
                  painter: _DropdownTrianglePainter(color: Color(0xFF777777)),
                ),
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
        // Figma IMG Box: 높이 136
        height: 136,
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
                  size: 56,
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

  // Figma Apply 버튼: figma_add_note 24 + 간격 3 + 19px 문구
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _submitBlue,
          disabledBackgroundColor: _submitBlue.withValues(alpha: 0.55),
          foregroundColor: Colors.white,
          disabledForegroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isSubmitting)
              const SizedBox(
                width: 24,
                height: 24,
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              )
            else
              SvgPicture.asset(
                'assets/icon/figma_add_note.svg',
                width: 24,
                height: 24,
              ),
            const SizedBox(width: 3),
            Text(
              _isSubmitting ? '신청 중...' : '명언 신청하기',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  // Figma Apply Fin: 400×241 안내 팝업으로 완료를 알리고, 확인 시 신청 화면을 닫는다.
  Future<void> _showCompletionPopup() async {
    await showAppNoticePopup(
      context,
      barrierDismissible: false,
      icon: const Icon(
        Icons.check_circle_outline,
        color: _appMutedGreen,
        size: 30,
      ),
      title: '명언 신청 완료',
      message: '관리자 검토 후 등록됩니다.\n신청용 공유 카운트만 0회로 초기화됩니다.',
      primaryLabel: '확인',
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    // 기존 완료 후 처리: 전면 광고 노출 요청(설정 화면의 카운트 재조회는 push 복귀 시 수행)
    widget.onInterstitialRequested();
  }
}

class _MyPageScreenState extends State<MyPageScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();

  // 사용자 데이터
  String _profileImageUrl = '';
  String _name = '';
  String _selectedLanguage = 'kor'; // 기본값: 한국어
  int _shareCount = 0;
  int _quoteRequestShareCount = 0;
  String? _deviceId;
  bool _isLoading = true;
  bool _isEditingName = false;
  bool _isSavingName = false;
  bool _nicknameSaved = false;
  bool _notificationsEnabled = false;
  bool _notificationBusy = false;
  TimeOfDay _notificationTime = const TimeOfDay(hour: 8, minute: 0);
  int _adminTapCount = 0;

  String _withCacheBuster(String imageUrl) {
    final separator = imageUrl.contains('?') ? '&' : '?';
    return '$imageUrl${separator}v=${DateTime.now().microsecondsSinceEpoch}';
  }

  // 공유 등급 계산
  String get _shareLevel {
    if (_shareCount >= 400) return '챔피언 / $_shareCount회';
    if (_shareCount >= 200) return '고수 / $_shareCount회';
    if (_shareCount >= 50) return '중급 / $_shareCount회';
    if (_shareCount >= 1) return '입문 / $_shareCount회';
    return '없음 / 0회';
  }

  // 공유 달성도: 명언 신청 조건(30회) 대비 신청용 공유 카운트 진행률(Figma "N / 30")
  int get _shareProgress {
    return ((_quoteRequestShareCount / _quoteRequestShareRequirement) * 100)
        .clamp(0, 100)
        .toInt();
  }

  bool get _hasChangedProfileImage => _profileImageUrl.trim().isNotEmpty;

  // 언어 옵션
  final Map<String, String> _languageOptions = {'kor': '한국어', 'eng': '영어'};

  @override
  void initState() {
    super.initState();
    _getDeviceId();
    _loadNotificationSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
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
          .select('share_count, quote_request_share_count')
          .eq('device_id', _deviceId!)
          .maybeSingle();

      final shareCount = shareData != null
          ? (shareData['share_count'] ?? 0) as int
          : 0;
      final quoteRequestShareCount = shareData != null
          ? (shareData['quote_request_share_count'] ?? 0) as int
          : 0;

      final response = await supabase
          .from('users')
          .select()
          .eq('device_id', _deviceId!)
          .maybeSingle();

      if (response != null) {
        // 데이터가 있으면 불러오기
        final savedName = response['user_id']?.toString().trim() ?? '';
        final displayName = savedName.isNotEmpty
            ? savedName
            : generateNickname(_deviceId!);
        setState(() {
          _name = displayName;
          _profileImageUrl = response['profile_image_url'] ?? '';
          _selectedLanguage = response['language'] ?? 'kor';
          _shareCount = shareCount;
          _quoteRequestShareCount = quoteRequestShareCount;
          _nameController.text = displayName;
          _isLoading = false;
        });
      } else {
        // 데이터가 없으면 랜덤 닉네임 표시
        final displayName = generateNickname(_deviceId!);
        setState(() {
          _name = displayName;
          _nameController.text = displayName;
          _selectedLanguage = 'kor';
          _shareCount = shareCount;
          _quoteRequestShareCount = quoteRequestShareCount;
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

  void _startEditingName() {
    if (_shareCount < 1 || _isSavingName || _nicknameSaved) return;

    setState(() => _isEditingName = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocusNode.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  Future<void> _handleNameAction() async {
    if (_shareCount < 1 || _isSavingName || _nicknameSaved) return;
    if (!_isEditingName) {
      _startEditingName();
      return;
    }
    await _saveUserToSupabase();
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

      if (!mounted) return;
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
    if (_shareCount < 10) {
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '프로필 사진은 공유 10회 완료 후 설정할 수 있어요. '
              '(현재 $_shareCount/10회)',
            ),
          ),
        );
      }
      return;
    }

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
      final fileExt = ImageMime.extensionOf(croppedFile.path);
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
              contentType: ImageMime.fromExtension(fileExt),
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

  Future<void> _showProfileImageMenu() async {
    final action = await showModalBottomSheet<_ProfileImageAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        final canDelete = _profileImageUrl.trim().isNotEmpty;

        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('사진 선택'),
                  onTap: () => Navigator.pop(
                    bottomSheetContext,
                    _ProfileImageAction.select,
                  ),
                ),
                ListTile(
                  enabled: canDelete,
                  leading: Icon(
                    Icons.delete_outline,
                    color: canDelete ? Colors.redAccent : Colors.grey,
                  ),
                  title: Text(
                    '사진 삭제',
                    style: TextStyle(
                      color: canDelete ? Colors.redAccent : Colors.grey,
                    ),
                  ),
                  onTap: canDelete
                      ? () => Navigator.pop(
                          bottomSheetContext,
                          _ProfileImageAction.delete,
                        )
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _ProfileImageAction.select:
        await _pickAndUploadImage();
        return;
      case _ProfileImageAction.delete:
        await _deleteProfileImage();
        return;
    }
  }

  String? _currentProfileImageStoragePath() {
    final deviceId = _deviceId;
    final uri = Uri.tryParse(_profileImageUrl.trim());
    if (deviceId == null || uri == null) return null;

    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf('avatars');
    if (bucketIndex < 0 || bucketIndex + 1 >= segments.length) return null;

    final storagePath = segments.sublist(bucketIndex + 1).join('/');
    final fileName = storagePath.split('/').last;
    if (!storagePath.startsWith('profiles/') ||
        !fileName.startsWith('$deviceId.')) {
      return null;
    }

    return storagePath;
  }

  Future<void> _deleteProfileImage() async {
    if (_profileImageUrl.trim().isEmpty) return;

    final deviceId = _deviceId;
    if (deviceId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('디바이스 정보를 가져오는 중입니다. 잠시 후 다시 시도해주세요')),
        );
      }
      return;
    }

    final previousImageUrl = _profileImageUrl;
    final storagePath = _currentProfileImageStoragePath();
    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text('프로필 사진 삭제 중...')));

    try {
      if (storagePath != null) {
        await supabase.storage.from('avatars').remove([storagePath]);
      }

      await supabase
          .from('users')
          .update({'profile_image_url': null})
          .eq('device_id', deviceId);

      await NetworkImage(previousImageUrl).evict();
      if (!mounted) return;

      setState(() => _profileImageUrl = '');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('프로필 사진이 삭제되었습니다.'),
            backgroundColor: _appMutedGreen,
          ),
        );
    } catch (error) {
      if (!mounted) return;

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('프로필 사진 삭제 실패: $error')));
      debugPrint('프로필 이미지 삭제 오류: $error');
    }
  }

  // Supabase에 사용자 정보 저장
  Future<void> _saveUserToSupabase() async {
    if (_shareCount < 1 || _isSavingName) return;

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

    setState(() => _isSavingName = true);

    try {
      final newName = _nameController.text.trim();

      // 닉네임 중복 확인 (자신의 device_id 제외)
      final isAvailable = await supabase.rpc(
        'is_nickname_available',
        params: {'p_user_id': newName},
      );

      if (isAvailable != true) {
        if (mounted) {
          setState(() => _isSavingName = false);
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
        _nameController.text = newName;
        _isEditingName = false;
        _isSavingName = false;
        _nicknameSaved = true;
      });
      _nameFocusNode.unfocus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ID 또는 이름이 저장되었습니다.'),
            backgroundColor: _appMutedGreen,
          ),
        );
      }

      // 저장 완료 상태를 잠시 보여준 뒤 다시 변경 가능 상태로 전환
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _nicknameSaved = false;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingName = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
      print('Supabase 저장 오류: $e');
    }
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final settings = await NotificationService.instance.loadSettings();
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = settings.enabled;
        _notificationTime = TimeOfDay(
          hour: settings.hour,
          minute: settings.minute,
        );
      });
    } catch (error) {
      debugPrint('알림 설정 불러오기 실패: $error');
    }
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    if (_notificationBusy) return;
    setState(() => _notificationBusy = true);

    try {
      if (enabled) {
        final granted = await NotificationService.instance.requestPermission();
        if (!granted) {
          if (!mounted) return;
          final message = NotificationService.instance.isSupported
              ? '알림 권한이 필요합니다. 기기 설정에서 힐링 하이 알림을 허용해 주세요.'
              : '이 기기에서는 명언 알림을 지원하지 않습니다.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
          return;
        }

        final quotes = await NotificationService.instance.loadQuotes(supabase);
        await NotificationService.instance.enable(
          hour: _notificationTime.hour,
          minute: _notificationTime.minute,
          quotes: quotes,
        );
      } else {
        await NotificationService.instance.disable(
          hour: _notificationTime.hour,
          minute: _notificationTime.minute,
        );
      }

      if (!mounted) return;
      setState(() => _notificationsEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? '매일 명언 알림을 설정했어요.' : '명언 알림을 해제했어요.'),
          backgroundColor: _appMutedGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('알림 설정을 변경하지 못했어요: $error')));
      debugPrint('알림 설정 변경 실패: $error');
    } finally {
      if (mounted) setState(() => _notificationBusy = false);
    }
  }

  Future<void> _selectNotificationTime() async {
    if (_notificationBusy) return;

    final selectedTime = await _showNotificationTimePicker();
    if (!mounted || selectedTime == null) return;
    if (selectedTime.hour == _notificationTime.hour &&
        selectedTime.minute == _notificationTime.minute) {
      return;
    }

    setState(() => _notificationBusy = true);
    try {
      final quotes = _notificationsEnabled
          ? await NotificationService.instance.loadQuotes(supabase)
          : null;
      await NotificationService.instance.updateTime(
        enabled: _notificationsEnabled,
        hour: selectedTime.hour,
        minute: selectedTime.minute,
        quotes: quotes,
      );

      if (!mounted) return;
      setState(() => _notificationTime = selectedTime);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('알림 시각을 변경했어요.'),
          backgroundColor: _appMutedGreen,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('알림 시각을 변경하지 못했어요: $error')));
      debugPrint('알림 시각 변경 실패: $error');
    } finally {
      if (mounted) setState(() => _notificationBusy = false);
    }
  }

  Future<TimeOfDay?> _showNotificationTimePicker() async {
    var selectedPeriod = _notificationTime.hour >= 12 ? 1 : 0;
    var selectedHour = _notificationTime.hour % 12;
    if (selectedHour == 0) selectedHour = 12;
    var selectedMinute = _notificationTime.minute;
    final periodController = FixedExtentScrollController(
      initialItem: selectedPeriod,
    );
    final hourController = FixedExtentScrollController(
      initialItem: 1200 + selectedHour - 1,
    );
    final minuteController = FixedExtentScrollController(
      initialItem: 6000 + selectedMinute,
    );

    // Figma: 선택 밑줄은 각 열(오전/오후 110, 시·분 숫자 45) 전체 폭
    Widget selectionLine() {
      return const Align(
        alignment: Alignment.bottomCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(color: _appMutedGreen),
          child: SizedBox(height: 2, width: double.infinity),
        ),
      );
    }

    TextStyle pickerTextStyle(bool isSelected) {
      return TextStyle(
        color: isSelected ? _appMutedGreen : const Color(0xFFAAAAAA),
        fontSize: 18,
        fontWeight: FontWeight.w500,
      );
    }

    final result = await showDialog<TimeOfDay>(
      context: context,
      barrierColor: const Color(0x9F000000),
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Container(
                  height: 346,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F4F1),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 125,
                        child: Column(
                          children: [
                            const SizedBox(height: 4),
                            Image.asset(
                              'assets/alarm_bell.png',
                              width: 30,
                              height: 30,
                            ),
                            const SizedBox(height: 15),
                            const Text(
                              '알림 시간 설정',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              '각 항목을 위아래로 움직여 시간을 설정해 주세요.',
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 15,
                                fontWeight: FontWeight.w300,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 100,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Expanded(
                                child: CupertinoPicker.builder(
                                  scrollController: periodController,
                                  itemExtent: 30,
                                  diameterRatio: 100,
                                  squeeze: 1,
                                  selectionOverlay: selectionLine(),
                                  childCount: 2,
                                  onSelectedItemChanged: (value) =>
                                      setModalState(
                                        () => selectedPeriod = value,
                                      ),
                                  itemBuilder: (_, index) => Center(
                                    child: Text(
                                      index == 0 ? '오전' : '오후',
                                      style: pickerTextStyle(
                                        selectedPeriod == index,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: CupertinoPicker.builder(
                                        scrollController: hourController,
                                        itemExtent: 30,
                                        diameterRatio: 100,
                                        squeeze: 1,
                                        selectionOverlay: selectionLine(),
                                        onSelectedItemChanged: (value) =>
                                            setModalState(
                                              () =>
                                                  selectedHour = value % 12 + 1,
                                            ),
                                        itemBuilder: (_, index) => Center(
                                          child: Text(
                                            '${index % 12 + 1}',
                                            style: pickerTextStyle(
                                              selectedHour == index % 12 + 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Figma: 숫자 ↔ 단위 간격 25
                                    const SizedBox(width: 25),
                                    const Expanded(
                                      child: Center(
                                        child: Text(
                                          '시',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: CupertinoPicker.builder(
                                        scrollController: minuteController,
                                        itemExtent: 30,
                                        diameterRatio: 100,
                                        squeeze: 1,
                                        selectionOverlay: selectionLine(),
                                        onSelectedItemChanged: (value) =>
                                            setModalState(
                                              () => selectedMinute = value % 60,
                                            ),
                                        itemBuilder: (_, index) => Center(
                                          child: Text(
                                            '${index % 60}',
                                            style: pickerTextStyle(
                                              selectedMinute == index % 60,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Figma: 숫자 ↔ 단위 간격 25
                                    const SizedBox(width: 25),
                                    const Expanded(
                                      child: Center(
                                        child: Text(
                                          '분',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 41,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    final hour = selectedPeriod == 0
                                        ? selectedHour % 12
                                        : (selectedHour % 12) + 12;
                                    Navigator.pop(
                                      dialogContext,
                                      TimeOfDay(
                                        hour: hour,
                                        minute: selectedMinute,
                                      ),
                                    );
                                  },
                                  child: const Center(
                                    child: Text(
                                      '확인',
                                      style: TextStyle(
                                        color: _appMutedGreen,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        height: 1.15,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => Navigator.pop(dialogContext),
                                  child: const Center(
                                    child: Text(
                                      '취소',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        height: 1.15,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    periodController.dispose();
    hourController.dispose();
    minuteController.dispose();
    return result;
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
        bottom: false,
        minimum: const EdgeInsets.only(top: 61),
        child: Column(
          children: [
            GestureDetector(
              key: TutorialTargets.profileTitle,
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
              child: const SizedBox(
                height: 43,
                width: double.infinity,
                child: Center(
                  child: Text(
                    '나만의 프로필로 힐링 하이를 채워보세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF595959),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 24),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Column(
                        children: [
                          GestureDetector(
                            key: TutorialTargets.profileImage,
                            onTap: _showProfileImageMenu,
                            child: SizedBox(
                              width: 148,
                              height: 146,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ClipOval(
                                      child: _profileImageUrl.isNotEmpty
                                          ? Image.network(
                                              _profileImageUrl,
                                              key: ValueKey(_profileImageUrl),
                                              fit: BoxFit.cover,
                                            )
                                          : Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                SvgPicture.asset(
                                                  'assets/icon/figma_profile_bg.svg',
                                                  width: 148,
                                                  height: 146,
                                                ),
                                                // PNG(불투명 #F5F5F5 배경)는 회색 원 위에 흰 사각형으로
                                                // 보이므로 + 아이콘은 코드로 그린다.
                                                const _ProfilePlusIcon(
                                                  size: 24.6,
                                                  thickness: 3,
                                                  color: _appMutedGreen,
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 2,
                                    right: 0,
                                    child: Container(
                                      width: 41,
                                      height: 41,
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: _appMutedGreen,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white),
                                      ),
                                      child: SvgPicture.asset(
                                        'assets/icon/figma_camera.svg',
                                        width: 29,
                                        height: 29,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 37,
                            child: Center(
                              child: !_hasChangedProfileImage
                                  ? const Text(
                                      '공유 10회 완료 후 프로필 사진 설정 가능',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Color(0xFFD74E44),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 38),
                    KeyedSubtree(
                      key: TutorialTargets.profileName,
                      child: _buildNameEditor(),
                    ),
                    const SizedBox(height: 38),
                    _buildNotificationSection(),
                    const SizedBox(height: 38),
                    KeyedSubtree(
                      key: TutorialTargets.profileShareLevel,
                      child: _buildInfoSection(
                        title: '공유 등급',
                        value: _shareLevel,
                        valueColor: const Color(0xFFD74E44),
                        onSearchTap: _showShareLeaderboard,
                        searchKey: TutorialTargets.profileLeaderboard,
                      ),
                    ),
                    const SizedBox(height: 38),
                    KeyedSubtree(
                      key: TutorialTargets.profileAchievement,
                      child: _buildAchievementSection(),
                    ),
                    const SizedBox(height: 38),
                    const Text(
                      '여러분의 한마디가 더 따뜻한 힐링 하이를 만들어갑니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 9),
                    _buildAppReviewButton(),
                    if (_quoteRequestShareCount >=
                        _quoteRequestShareRequirement) ...[
                      const SizedBox(height: 21),
                      _buildQuoteRequestButton(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTitle(
    String title, {
    VoidCallback? onHelp,
    String? tooltip,
    Key? helpKey,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                height: 21 / 18,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
          ),
          if (onHelp != null)
            IconButton(
              key: helpKey,
              onPressed: onHelp,
              tooltip: tooltip,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 20, height: 20),
              style: IconButton.styleFrom(
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: SvgPicture.asset(
                'assets/icon/figma_help.svg',
                width: 20,
                height: 20,
              ),
            ),
        ],
      ),
    );
  }

  // Figma 시안에 언어 섹션이 없어 화면에는 노출하지 않는다(데이터 흐름 참고용).
  // ignore: unused_element
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
                color: Colors.grey.withValues(alpha: 0.1),
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

  Widget _buildNameEditor() {
    final canChangeName = _shareCount >= 1;
    final isActionEnabled = canChangeName && !_isSavingName && !_nicknameSaved;
    final buttonLabel = _nicknameSaved
        ? '완료'
        : _isSavingName
        ? '변경 중...'
        : '변경하기';
    final guideText = _isEditingName
        ? '변경하고 싶은 ID 또는 이름을 입력하세요.'
        : canChangeName
        ? null
        : '공유 1회 완료 후 이름 설정 가능';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSettingsTitle('ID 또는 이름'),
        const SizedBox(height: 11),
        Container(
          height: 62,
          padding: const EdgeInsets.only(left: 23, right: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  focusNode: _nameFocusNode,
                  readOnly: !_isEditingName,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  enableInteractiveSelection: _isEditingName,
                  onSubmitted: (_) => _handleNameAction(),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'ID 또는 이름을 입력하세요',
                    hintStyle: TextStyle(
                      color: Color(0xFFBDBDBD),
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              SizedBox(
                width: 98,
                height: 40,
                child: TextButton(
                  onPressed: isActionEnabled ? _handleNameAction : null,
                  style: TextButton.styleFrom(
                    backgroundColor: _appMutedGreen,
                    foregroundColor: const Color(0xFFF6F4F1),
                    disabledForegroundColor: const Color(0xFFF6F4F1),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(40),
                    ),
                  ),
                  child: Text(
                    buttonLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (guideText != null) ...[
          const SizedBox(height: 11),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 21),
            child: Text(
              guideText,
              style: const TextStyle(
                color: Color(0xFFD74E44),
                fontSize: 14,
                height: 17 / 14,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
        ],
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
        'profileImageUrl': row['profile_image_url']?.toString() ?? '',
        'shareCount': count is int
            ? count
            : int.tryParse(count?.toString() ?? '') ?? 0,
        'isCurrentUser': row['is_current_user'] == true,
        'rank': rank is int ? rank : int.tryParse(rank?.toString() ?? '') ?? 0,
      };
    }).toList();
  }

  ({String label, int remaining}) _nextShareTier(int shareCount) {
    if (shareCount < 1) return (label: '입문', remaining: 1 - shareCount);
    if (shareCount < 50) return (label: '중급', remaining: 50 - shareCount);
    if (shareCount < 200) return (label: '고수', remaining: 200 - shareCount);
    if (shareCount < 400) return (label: '챔피언', remaining: 400 - shareCount);
    return (label: '챔피언', remaining: 0);
  }

  Widget _buildLeaderboardProfile(String imageUrl) {
    final fallback = Container(
      width: 41,
      height: 41,
      decoration: const BoxDecoration(
        color: Color(0xFFE4E4E4),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.person_outline, color: Colors.black, size: 29),
    );

    if (imageUrl.trim().isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: 41,
        height: 41,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _buildLeaderboardRank(int rank) {
    // Figma Rank Card: 1~3위는 프로필 사진 왼쪽에 41px 메달. 흔들리는 애니메이션으로 재생한다.
    if (rank >= 1 && rank <= 3) {
      return AnimatedRankMedal(rank: rank, size: 41);
    }

    return SizedBox(
      width: 41,
      child: Text(
        '$rank',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _appMutedGreen,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildLeaderboardCard(Map<String, dynamic> entry) {
    final rank = entry['rank'] as int;
    final isCurrentUser = entry['isCurrentUser'] as bool;

    return Semantics(
      label: isCurrentUser ? '내 리더보드 순위' : null,
      child: Container(
        // Figma Rank Card: 높이 63
        height: 63,
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          children: [
            _buildLeaderboardRank(rank),
            const SizedBox(width: 25),
            // 내 사진은 저장/삭제 직후의 설정 상태를 사용한다.
            // 구버전 랭킹 RPC는 profile_image_url을 반환하지 않을 수 있다.
            _buildLeaderboardProfile(
              isCurrentUser
                  ? _profileImageUrl
                  : entry['profileImageUrl'] as String,
            ),
            const SizedBox(width: 25),
            Expanded(
              child: Text(
                entry['name'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${entry['shareCount']}회',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyLeaderboardRank(Map<String, dynamic>? currentEntry) {
    final shareCount = currentEntry?['shareCount'] as int? ?? _shareCount;
    final nextTier = _nextShareTier(shareCount);
    final rankText = currentEntry == null ? '-' : '${currentEntry['rank']}위';

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3EAE3),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          const Text(
            '내 순위',
            style: TextStyle(
              color: Color(0xFF161616),
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 25 / 18,
            ),
          ),
          const SizedBox(width: 25),
          Text(
            rankText,
            style: const TextStyle(
              color: _appMutedGreen,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 25 / 19,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text.rich(
              nextTier.remaining == 0
                  ? TextSpan(
                      children: [
                        const TextSpan(text: '최고 등급('),
                        TextSpan(
                          text: nextTier.label,
                          style: const TextStyle(
                            color: _appMutedGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: ')을 달성했어요'),
                      ],
                    )
                  : TextSpan(
                      children: [
                        const TextSpan(text: '다음 등급('),
                        TextSpan(
                          text: nextTier.label,
                          style: const TextStyle(
                            color: _appMutedGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: ')까지 남은 공유 횟수 '),
                        TextSpan(
                          text: '${nextTier.remaining}',
                          style: const TextStyle(
                            color: _appMutedGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: '회'),
                      ],
                    ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 25 / 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 바텀시트 상단 힌트(Figma Header: 높이 23, 19px)
  Widget _buildSheetHeaderHint(String text) {
    return SizedBox(
      height: 23,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFCBCBCB),
              fontSize: 19,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // 바텀시트 핸들(Figma close: 48×4)
  Widget _buildSheetHandle() {
    return Container(
      width: 48,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFF757575),
        borderRadius: BorderRadius.circular(8.5),
      ),
    );
  }

  Future<void> _showShareLeaderboard() async {
    final leaderboardFuture = _loadShareLeaderboard();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.82,
        alignment: Alignment.bottomCenter,
        child: Column(
          children: [
            _buildSheetHeaderHint('위로 올려 더 보기 / 아래로 내려 돌아가기'),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  15,
                  19,
                  15,
                  19 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF6F4F1),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Column(
                  children: [
                    _buildSheetHandle(),
                    const SizedBox(height: 16),
                    // Figma Info: 좌우 20(화면 35), 아이콘 컨테이너 73(rank_icon 67)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 3,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 73,
                            height: 73,
                            child: Center(
                              child: Image.asset(
                                'assets/rank_icon.png',
                                width: 67,
                                height: 67,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Text(
                            '공유 랭킹',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: SizedBox(
                              height: 17,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '힐링 하이를 얼마나 자주 나누었을까요?',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 19),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: leaderboardFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: _appMutedGreen,
                              ),
                            );
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
                              _buildMyLeaderboardRank(currentEntry),
                              const SizedBox(height: 19),
                              Expanded(
                                child: entries.isEmpty
                                    ? const Center(
                                        child: Text('표시할 사용자가 없습니다.'),
                                      )
                                    : ListView.separated(
                                        padding: EdgeInsets.zero,
                                        itemCount: entries.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 19),
                                        itemBuilder: (context, index) =>
                                            _buildLeaderboardCard(
                                              entries[index],
                                            ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSection() {
    final formattedTime =
        '${_notificationTime.hour.toString().padLeft(2, '0')} : '
        '${_notificationTime.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 19, child: _buildSettingsTitle('알림 설정')),
        const SizedBox(height: 11),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(22, 8, 0, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 좁은 폭에서 "다."만 둘째 줄로 떨어지지 않도록 1줄로 축소 표시
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '매일 힐링 하이의 명언 알림을 받습니다.',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w300,
                          height: 19 / 16,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '알림 시각',
                      style: TextStyle(
                        fontSize: 16,
                        height: 19 / 16,
                        fontWeight: FontWeight.w300,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 127,
              child: Column(
                children: [
                  SizedBox(
                    width: 65,
                    height: 27,
                    child: Semantics(
                      label: '매일 명언 알림',
                      toggled: _notificationsEnabled,
                      child: TextButton(
                        onPressed: _notificationBusy
                            ? null
                            : () => _setNotificationsEnabled(
                                !_notificationsEnabled,
                              ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: const StadiumBorder(),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 65,
                          height: 27,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3.6,
                            vertical: 2.7,
                          ),
                          decoration: BoxDecoration(
                            color: _notificationsEnabled
                                ? _appMutedGreen
                                : const Color(0xFFE2E2E2),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 180),
                            alignment: _notificationsEnabled
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              width: 29,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(99),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1F000000),
                                    blurRadius: 2,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: '알림 시각 $formattedTime, 변경하려면 두 번 탭하세요',
                    child: InkWell(
                      onTap: _notificationBusy ? null : _selectNotificationTime,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: _notificationBusy ? 0.45 : 1,
                          child: Text(
                            formattedTime,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              height: 19 / 16,
                              color: Color(0xFFBDBDBD),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoSection({
    required String title,
    required String value,
    Color? valueColor,
    VoidCallback? onSearchTap,
    Key? searchKey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSettingsTitle(
          title,
          onHelp: onSearchTap,
          tooltip: '공유 리더보드 보기',
          helpKey: searchKey,
        ),
        const SizedBox(height: 11),
        Container(
          width: double.infinity,
          height: 62,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 23, right: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 21,
              color: valueColor ?? Colors.black,
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
      child: ElevatedButton(
        onPressed: () async {
          final fallbackName = _deviceId != null
              ? generateNickname(_deviceId!)
              : '';
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _QuoteRequestPage(
                displayName: _name.isNotEmpty ? _name : fallbackName,
                onInterstitialRequested: widget.onInterstitialRequested,
              ),
            ),
          );
          if (!mounted) return;
          await _loadUserData();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF538CD2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/icon/figma_add_note.svg',
              width: 24,
              height: 24,
            ),
            // Figma: 아이콘 ↔ 텍스트 간격 3
            const SizedBox(width: 3),
            const Text(
              '명언 신청하기',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openStoreReview() async {
    try {
      final configuredAppStoreId = dotenv.env['APP_STORE_ID']?.trim();
      await InAppReview.instance.openStoreListing(
        appStoreId: configuredAppStoreId?.isNotEmpty == true
            ? configuredAppStoreId
            : null,
      );
    } catch (error) {
      debugPrint('앱 스토어 열기 실패: $error');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('스토어 화면을 열 수 없어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  // Figma Review: "리뷰 남기기 / 다음에" 2버튼 안내 팝업 후 스토어로 이동
  Future<void> _showReviewPopup() async {
    final action = await showAppNoticePopup(
      context,
      icon: Image.asset(
        'assets/icon/review_store.png',
        width: 30,
        height: 30,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
      title: '힐링 하이는 어떠셨나요?',
      message: '힐링 하이가 도움이 되었다면\n스토어에 리뷰를 남겨 주세요.',
      primaryLabel: '리뷰 남기기',
      secondaryLabel: '다음에',
    );
    if (!mounted || action != AppNoticeAction.primary) return;
    await _openStoreReview();
  }

  Widget _buildAppReviewButton() {
    return SizedBox(
      width: double.infinity,
      height: 53,
      child: ElevatedButton(
        onPressed: _showReviewPopup,
        style: ElevatedButton.styleFrom(
          backgroundColor: _appMutedGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          elevation: 0,
        ),
        child: const Text(
          '힐링 하이 리뷰 작성하기',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
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
                              final requestQuoteId = await _submitQuoteRequest(
                                quote: quoteController.text.trim(),
                                author: authorController.text.trim(),
                                category: selectedCategory!,
                              );

                              if (selectedImage != null) {
                                try {
                                  final bytes = await File(
                                    selectedImage!.path,
                                  ).readAsBytes();
                                  final fileExt = ImageMime.extensionOf(
                                    selectedImage!.path,
                                  );
                                  final filePath =
                                      'quote_requests/${InstallationIdentity.id}/$requestQuoteId.$fileExt';

                                  await supabase.storage
                                      .from('avatars')
                                      .uploadBinary(
                                        filePath,
                                        bytes,
                                        fileOptions: FileOptions(
                                          upsert: true,
                                          contentType: ImageMime.fromExtension(
                                            fileExt,
                                          ),
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
                              if (mounted) {
                                setState(() => _quoteRequestShareCount = 0);
                              }
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

  // Figma Settings (Ranking Guide): 랭킹 시트와 같은 규격의 바텀시트로 공유 달성도를 안내한다.
  // (시안의 제목 "공유 랭킹"은 복붙 잔재로 보고 "공유 달성도란?"을 유지)
  Future<void> _showAchievementInfoDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.82,
        alignment: Alignment.bottomCenter,
        child: Column(
          children: [
            _buildSheetHeaderHint('아래로 내려 돌아가기'),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(
                  15,
                  19,
                  15,
                  19 + MediaQuery.paddingOf(context).bottom,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFF6F4F1),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: Column(
                  children: [
                    _buildSheetHandle(),
                    const SizedBox(height: 16),
                    // Figma Info: 높이 33(상하 3), 제목 중앙
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 3),
                      child: SizedBox(
                        height: 27,
                        child: Center(
                          child: Text(
                            '공유 달성도란?',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 19),
                    // Figma share_illust: 309×146 중앙
                    SizedBox(
                      width: 309,
                      height: 146,
                      child: ClipRect(
                        child: Image.asset(
                          'assets/share_illust.png',
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, -0.17),
                        ),
                      ),
                    ),
                    const SizedBox(height: 19),
                    // Figma 본문 박스: 409×412(좌우 15), 내부 25/10, 버튼 없음
                    Flexible(
                      child: Container(
                        width: double.infinity,
                        height: 412,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 25,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3EAE3),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: const Center(
                          child: SingleChildScrollView(
                            child: Text(
                              '명언을 공유할 때마다\n'
                              '공유 달성도가 차곡차곡 올라가요.\n\n'
                              '달성도를 모두 채우면\n'
                              '원하는 명언을 제작자에게 직접 신청할 수 있어요.\n\n'
                              '신청한 명언은 제작자의 확인 후\n'
                              '힐링 하이에 소개될 수 있어요.\n\n'
                              '여러분의 공유가\n'
                              '힐링 하이에 새로운 문장을 더해요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAchievementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSettingsTitle(
          '공유 달성도',
          onHelp: _showAchievementInfoDialog,
          tooltip: '공유 달성도 안내',
        ),
        const SizedBox(height: 11),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Semantics(
            label: '공유 달성도',
            value: '$_shareProgress%',
            child: SizedBox(
              height: 18,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: LinearProgressIndicator(
                      value: _shareProgress / 100,
                      minHeight: 18,
                      backgroundColor: const Color(0xFFEEEEEE),
                      color: _appMutedGreen,
                    ),
                  ),
                  Text(
                    '$_quoteRequestShareCount / $_quoteRequestShareRequirement',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      color: _shareProgress >= 55
                          ? Colors.white
                          : const Color(0xFF527455),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Figma 카테고리 Select 화살표(12×8, 아래 방향 삼각형)
class _DropdownTrianglePainter extends CustomPainter {
  const _DropdownTrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _DropdownTrianglePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

/// 프로필 사진 미설정 시 회색 원 중앙에 표시하는 + 아이콘(배경 없음).
class _ProfilePlusIcon extends StatelessWidget {
  const _ProfilePlusIcon({
    required this.size,
    required this.thickness,
    required this.color,
  });

  final double size;
  final double thickness;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bar = BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(thickness / 2),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: size, height: thickness, decoration: bar),
          Container(width: thickness, height: size, decoration: bar),
        ],
      ),
    );
  }
}
