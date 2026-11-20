import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../providers/app_providers.dart';
import '../services/lecture_recorder_service.dart';
import '../services/semantic_search_service.dart';
import 'session_detail_screen.dart';

/// Semantic search screen finding relevant lecture segments by meaning (Cosine
/// Similarity) or offline keyword fallback, with 1-tap audio timestamp jump.
class SemanticSearchScreen extends ConsumerStatefulWidget {
  const SemanticSearchScreen({super.key, this.initialCourseId});

  final int? initialCourseId;

  @override
  ConsumerState<SemanticSearchScreen> createState() =>
      _SemanticSearchScreenState();
}

class _SemanticSearchScreenState extends ConsumerState<SemanticSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  int? _selectedCourseId;
  bool _isSearching = false;
  bool _hasSearched = false;
  SemanticSearchResponse? _response;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _selectedCourseId = widget.initialCourseId;
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _executeSearch() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _searchError = null;
    });

    try {
      final result = await ref.read(semanticSearchServiceProvider).search(
            query: query,
            courseId: _selectedCourseId,
          );
      if (mounted) {
        setState(() {
          _isSearching = false;
          _response = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchError = 'Gagal mencari catatan: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(coursesProvider).value ?? const [];
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tanya Catatan (Semantic Search)'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _executeSearch(),
                    decoration: InputDecoration(
                      hintText: 'Misal: Apa bedanya mitosis dan meiosis?',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _queryController.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Bersihkan',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _queryController.clear();
                                setState(() {
                                  _response = null;
                                  _hasSearched = false;
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSearching ? null : _executeSearch,
                  child: const Text('Cari'),
                ),
              ],
            ),
          ),
          if (courses.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Semua Mata Kuliah'),
                      selected: _selectedCourseId == null,
                      onSelected: (_) {
                        setState(() => _selectedCourseId = null);
                        if (_queryController.text.trim().isNotEmpty) {
                          _executeSearch();
                        }
                      },
                    ),
                  ),
                  ...courses.map(
                    (course) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(course.name),
                        selected: _selectedCourseId == course.id,
                        onSelected: (_) {
                          setState(() => _selectedCourseId = course.id);
                          if (_queryController.text.trim().isNotEmpty) {
                            _executeSearch();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_response != null && !_isSearching)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Row(
                children: [
                  Icon(
                    _response!.usedSemanticVectors
                        ? Icons.psychology_outlined
                        : Icons.text_fields,
                    size: 16,
                    color: _response!.usedSemanticVectors
                        ? colorScheme.primary
                        : Colors.amber,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _response!.usedSemanticVectors
                          ? 'Semantic Vector Search (Makna) • ${_response!.hits.length} hasil'
                          : 'Pencarian Kata Kunci Offline • ${_response!.hits.length} hasil',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildResultsBody(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildResultsBody(ColorScheme colorScheme) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_searchError!, textAlign: TextAlign.center),
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.manage_search_outlined,
                size: 56,
                color: colorScheme.primary.withValues(alpha: 0.75),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cari Materi Berdasarkan Makna',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Ketik pertanyaan natural tentang penjelasan dosen. Aplikasi mencari kemiripan makna di seluruh catatan lokal dan menunjuk menit rekaman yang tepat.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hits = _response?.hits ?? const [];
    if (hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Tidak ditemukan bagian catatan yang cocok. Pastikan rekaman kuliah sudah diproses dengan AI atau coba kata kunci lain.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      itemCount: hits.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final hit = hits[index];
        final accent = AppTheme.parseHexColor(hit.courseColorHex);
        final timeText =
            LectureRecorderService.formatDurationMs(hit.segment.startMs);
        final percent = (hit.score * 100).round().clamp(1, 100);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${hit.courseName} • ${hit.session.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$percent% cocok',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  hit.segment.textContent,
                  style: const TextStyle(fontSize: 13.5, height: 1.45),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SessionDetailScreen(
                            initialSession: hit.session,
                            initialSeekMs: hit.segment.startMs,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text('Putar di Menit $timeText'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
