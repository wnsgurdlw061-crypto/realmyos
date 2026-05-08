#!/bin/bash
# UnifiedArch OS 문서 생성 시스템
# 실제로 동작하는 완전한 문서 빌드 시스템

set -euo pipefail

# 버전 정보
VERSION="1.0.0"
BUILD_DATE=$(date +%Y%m%d)

# 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$PROJECT_ROOT/docs"
BUILD_DIR="$PROJECT_ROOT/build/docs"
OUTPUT_DIR="$PROJECT_ROOT/docs/output"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 헬퍼 함수
banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
 ____  _ _ _   _                     _      
| __ )(_) | | | | __ _ _ __   __ _ (_)_ __ 
|  _ \| | | |_| |/ _` | '_ \ / _` || | '_ \
| |_) | | |  _  | (_| | | | | (_| || | | | |
|____/|_|_|_| |_|\__,_|_| |_|\__,_||_|_| |_|
                                              
         문서 생성 시스템 v1.0
EOF
    echo -e "${NC}"
}

# 환경 확인
check_doc_environment() {
    log_step "문서 생성 환경 확인 중..."
    
    # 필수 도구 확인
    local required_tools=("pandoc" "make" "find" "sed" "grep")
    local optional_tools=("wkhtmltopdf" "plantuml" "graphviz" "python3")
    
    local missing_required=()
    local missing_optional=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_required+=("$tool")
        fi
    done
    
    for tool in "${optional_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_optional+=("$tool")
        fi
    done
    
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        log_error "필수 도구 없음: ${missing_required[*]}"
        exit 1
    fi
    
    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        log_warning "선택적 도구 없음: ${missing_optional[*]}"
    fi
    
    # 작업 디렉토리 생성
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"/{html,pdf,man}
    
    log_success "문서 생성 환경 확인 완료"
}

# 마크다운을 HTML로 변환
convert_markdown_to_html() {
    local input_file="$1"
    local output_file="$2"
    local title="${3:-}"
    
    log_info "변환: $(basename "$input_file") → HTML"
    
    # CSS 스타일 생성
    local css_content='
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    line-height: 1.6;
    max-width: 800px;
    margin: 0 auto;
    padding: 20px;
    color: #333;
    background: #fff;
}
h1, h2, h3, h4, h5, h6 {
    color: #2c3e50;
    margin-top: 2em;
    margin-bottom: 1em;
}
h1 {
    border-bottom: 2px solid #3498db;
    padding-bottom: 0.5em;
}
h2 {
    border-bottom: 1px solid #bdc3c7;
    padding-bottom: 0.3em;
}
code {
    background: #f8f9fa;
    padding: 2px 4px;
    border-radius: 3px;
    font-family: "SFMono-Regular", Consolas, monospace;
}
pre {
    background: #f8f9fa;
    padding: 1em;
    border-radius: 5px;
    overflow-x: auto;
}
pre code {
    background: none;
    padding: 0;
}
blockquote {
    border-left: 4px solid #3498db;
    margin: 0;
    padding-left: 1em;
    color: #7f8c8d;
}
table {
    border-collapse: collapse;
    width: 100%;
    margin: 1em 0;
}
th, td {
    border: 1px solid #ddd;
    padding: 8px;
    text-align: left;
}
th {
    background: #f2f2f2;
}
a {
    color: #3498db;
    text-decoration: none;
}
a:hover {
    text-decoration: underline;
}
.toc {
    background: #f8f9fa;
    border: 1px solid #ddd;
    padding: 1em;
    margin: 1em 0;
    border-radius: 5px;
}
.toc h2 {
    margin-top: 0;
    border-bottom: none;
}
'
    
    # HTML 헤더 생성
    local html_header="<html>
<head>
<meta charset=\"UTF-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
<title>${title:-UnifiedArch OS Documentation}</title>
<style>
${css_content}
</style>
</head>
<body>"
    
    # HTML 푸터 생성
    local html_footer="</body>
</html>"
    
    # pandoc으로 변환
    if pandoc -f markdown -t html5 --standalone \
           --metadata title="$title" \
           --css=<(echo "$css_content") \
           -o "$output_file" \
           "$input_file" 2>/dev/null; then
        log_success "HTML 변환 완료: $(basename "$output_file")"
    else
        log_warning "pandoc 변환 실패, 수동 변환 시도"
        
        # 간단한 수동 변환
        {
            echo "$html_header"
            echo "<h1>${title:-UnifiedArch OS Documentation}</h1>"
            sed 's/^#\(#\)\? /<h\1>/' "$input_file" | \
            sed 's/^##\(#\)\? /<h\1>/' | \
            sed 's/^###\(#\)\? /<h\1>/' | \
            sed 's/^\*\(.*\)\*/<strong>\1<\/strong>/' | \
            sed 's/^\*\(.*\)/<li>\1<\/li>/' | \
            sed 's/^```/<pre><code>/' | \
            sed 's/^```/<\/code><\/pre>/' | \
            sed 's/`\(.*\)`/<code>\1<\/code>/g'
            echo "$html_footer"
        } > "$output_file"
    fi
}

# 마크다운을 PDF로 변환
convert_markdown_to_pdf() {
    local input_file="$1"
    local output_file="$2"
    local title="${3:-}"
    
    log_info "변환: $(basename "$input_file") → PDF"
    
    if command -v wkhtmltopdf >/dev/null 2>&1; then
        # HTML로 먼저 변환 후 PDF로 변환
        local temp_html="$BUILD_DIR/temp_$(basename "$input_file" .md).html"
        
        convert_markdown_to_html "$input_file" "$temp_html" "$title"
        
        if wkhtmltopdf --page-size A4 --margin-top 1cm --margin-bottom 1cm \
                       --margin-left 1cm --margin-right 1cm \
                       --enable-local-file-access \
                       "$temp_html" "$output_file" 2>/dev/null; then
            log_success "PDF 변환 완료: $(basename "$output_file")"
        else
            log_warning "PDF 변환 실패"
        fi
        
        rm -f "$temp_html"
    else
        log_warning "wkhtmltopdf 없음 - PDF 변환 건너뜀"
    fi
}

# 매뉴얼 페이지 생성
generate_man_pages() {
    log_step "매뉴얼 페이지 생성 중..."
    
    # 도구별 매뉴얼 생성
    local tools=("install.sh" "config-manager.sh" "package-manager.sh")
    
    for tool in "${tools[@]}"; do
        local tool_path="$PROJECT_ROOT/src/$tool"
        local man_name=$(basename "$tool" .sh)
        local man_file="$OUTPUT_DIR/man/$man_name.1"
        
        if [[ -f "$tool_path" ]]; then
            # 간단한 man 페이지 생성
            cat > "$man_file" << EOF
.TH $man_name 1 "UnifiedArch OS" "UnifiedArch OS Manual"
.SH NAME
$man_name - UnifiedArch OS $(basename "$tool" .sh) tool
.SH SYNOPSIS
.B $man_name
[options] [arguments]
.SH DESCRIPTION
UnifiedArch OS $(basename "$tool" .sh) 도구입니다.
.SH OPTIONS
.TP
.B --help
도움말을 표시합니다.
.SH AUTHOR
UnifiedArch OS Team
.SH SEE ALSO
unifiedarch(1)
EOF
            
            log_success "매뉴얼 페이지 생성됨: $man_name.1"
        fi
    done
}

# API 문서 생성
generate_api_docs() {
    log_step "API 문서 생성 중..."
    
    # 헤더 파일에서 API 문서 생성
    local header_files=("$PROJECT_ROOT/include/network_security.h" "$PROJECT_ROOT/include/security_tools.h")
    
    for header_file in "${header_files[@]}"; do
        if [[ -f "$header_file" ]]; then
            local basename=$(basename "$header_file" .h)
            local api_doc="$OUTPUT_DIR/html/api_$basename.html"
            
            # 간단한 API 문서 생성
            {
                echo "<html><head><title>API: $basename</title>"
                echo "<style>body { font-family: monospace; line-height: 1.8; }"
                echo "pre { background: #f5f5f5; padding: 1em; }</style></head><body>"
                echo "<h1>API Documentation: $basename</h1>"
                
                # 함수 프로토타입 추출
                grep -E "^[a-zA-Z_][a-zA-Z0-9_]*\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\(" "$header_file" | \
                sed 's/^/ <br><pre>/' | sed 's/$/<\/pre>/' || true
                
                echo "</body></html>"
            } > "$api_doc"
            
            log_success "API 문서 생성됨: api_$basename.html"
        fi
    done
}

# 인덱스 페이지 생성
generate_index() {
    log_step "인덱스 페이지 생성 중..."
    
    local index_file="$OUTPUT_DIR/html/index.html"
    
    # 모든 HTML 파일 목록 수집
    local html_files=($(find "$OUTPUT_DIR/html" -name "*.html" -not -name "index.html" | sort))
    
    cat > "$index_file" << EOF
<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>UnifiedArch OS Documentation</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
               line-height: 1.6; max-width: 800px; margin: 0 auto; padding: 20px; }
        h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 0.5em; }
        .toc { background: #f8f9fa; border: 1px solid #ddd; padding: 1em; border-radius: 5px; }
        .toc ul { list-style: none; padding: 0; }
        .toc li { margin: 0.5em 0; }
        .toc a { color: #3498db; text-decoration: none; }
        .toc a:hover { text-decoration: underline; }
        .version { color: #7f8c8d; font-size: 0.9em; }
    </style>
</head>
<body>
    <h1>UnifiedArch OS Documentation</h1>
    <p class="version">Version: $VERSION | Build Date: $BUILD_DATE</p>
    
    <div class="toc">
        <h2>목차</h2>
        <ul>
EOF

    # 목차 생성
    for html_file in "${html_files[@]}"; do
        local filename=$(basename "$html_file" .html)
        local title=$(grep -o '<title>[^<]*</title>' "$html_file" | sed 's/<title>\(.*\)<\/title>/\1/' | head -n1)
        
        echo "            <li><a href=\"$filename.html\">${title:-$filename}</a></li>" >> "$index_file"
    done
    
    cat >> "$index_file" << EOF
        </ul>
    </div>
    
    <h2>빠른 링크</h2>
    <ul>
        <li><a href="phase1-architecture.html">Phase 1: 기본 아키텍처</a></li>
        <li><a href="phase2-installation.html">Phase 2: 설치 시스템</a></li>
        <li><a href="api_network_security.html">네트워크 보안 API</a></li>
        <li><a href="api_security_tools.html">보안 도구 API</a></li>
    </ul>
    
    <h2>도구 문서</h2>
    <ul>
        <li><a href="tools/install.html">설치 프로그램</a></li>
        <li><a href="tools/config-manager.html">설정 관리자</a></li>
        <li><a href="tools/package-manager.html">패키지 관리자</a></li>
    </ul>
    
    <h2>개발자 리소스</h2>
    <ul>
        <li><a href="kernel-modules.html">커널 모듈</a></li>
        <li><a href="build-system.html">빌드 시스템</a></li>
        <li><a href="testing.html">테스트 가이드</a></li>
    </ul>
    
    <h2>커뮤니티</h2>
    <ul>
        <li><a href="https://github.com/unifiedarch/unifiedarch">GitHub 저장소</a></li>
        <li><a href="https://docs.unifiedarch.org">온라인 문서</a></li>
        <li><a href="https://community.unifiedarch.org">커뮤니티 포럼</a></li>
    </ul>
    
    <footer>
        <p><small>&copy; 2026 UnifiedArch OS Project. Licensed under GPL v3.0.</small></p>
    </footer>
</body>
</html>
EOF

    log_success "인덱스 페이지 생성됨"
}

# 도구별 문서 생성
generate_tool_docs() {
    log_step "도구별 문서 생성 중..."
    
    local tools_dir="$OUTPUT_DIR/html/tools"
    mkdir -p "$tools_dir"
    
    # 설치 프로그램 문서
    local install_script="$PROJECT_ROOT/src/installer/install.sh"
    if [[ -f "$install_script" ]]; then
        local install_doc="$tools_dir/install.html"
        
        {
            echo "<html><head><title>설치 프로그램 문서</title>"
            echo "<style>body { font-family: sans-serif; line-height: 1.6; }"
            echo "code { background: #f5f5f5; padding: 2px 4px; }</style></head><body>"
            echo "<h1>UnifiedArch OS 설치 프로그램</h1>"
            echo "<h2>개요</h2>"
            echo "<p>UnifiedArch OS 설치 프로그램은 Arch Linux 기반의 자동화된 설치 시스템입니다.</p>"
            echo "<h2>사용법</h2>"
            echo "<pre>sudo ./install.sh</pre>"
            echo "<h2>기능</h2>"
            echo "<ul>"
            grep -E "^[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$install_script" | \
            head -20 | \
            sed 's/().*/<\/li>/' | \
            sed 's/^/            <li>/' | \
            sed 's/^            <li>/<li>/' || true
            echo "</ul>"
            echo "</body></html>"
        } > "$install_doc"
        
        log_success "설치 프로그램 문서 생성됨"
    fi
    
    # 다른 도구들에 대해서도 유사하게 문서 생성
    local config_manager="$PROJECT_ROOT/src/tools/config-manager.sh"
    if [[ -f "$config_manager" ]]; then
        local config_doc="$tools_dir/config-manager.html"
        
        {
            echo "<html><head><title>설정 관리자 문서</title>"
            echo "<style>body { font-family: sans-serif; line-height: 1.6; }"
            echo "code { background: #f5f5f5; padding: 2px 4px; }</style></head><body>"
            echo "<h1>설정 관리자</h1>"
            echo "<h2>개요</h2>"
            echo "<p>UnifiedArch OS 설정 관리자는 YAML 기반의 설정 관리 시스템입니다.</p>"
            echo "<h2>명령어</h2>"
            grep -E '^[[:space:]]*"[a-z]+")' "$config_manager" | \
            sed 's/^[[:space:]]*"\([^"]*\)".*/<li>\1<\/li>/' | \
            sed -i '1i<ul>' && sed -i '$a</ul>' || true
            echo "</body></html>"
        } > "$config_doc"
        
        log_success "설정 관리자 문서 생성됨"
    fi
}

# 검색 기능 추가
add_search_functionality() {
    log_step "검색 기능 추가 중..."
    
    # 간단한 JavaScript 검색 기능
    local search_js='
function searchDocs() {
    const query = document.getElementById("searchInput").value.toLowerCase();
    const content = document.body;
    const text = content.textContent.toLowerCase();
    
    if (query.length < 2) return;
    
    // 기존 하이라이트 제거
    const highlights = document.querySelectorAll(".search-highlight");
    highlights.forEach(el => {
        const parent = el.parentNode;
        parent.replaceChild(document.createTextNode(el.textContent), el);
        parent.normalize();
    });
    
    if (query && text.includes(query)) {
        const walker = document.createTreeWalker(
            document.body,
            NodeFilter.SHOW_TEXT,
            null,
            false
        );
        
        let node;
        while (node = walker.nextNode()) {
            const text = node.textContent;
            const index = text.toLowerCase().indexOf(query);
            
            if (index >= 0 && node.parentNode.tagName !== "SCRIPT") {
                const span = document.createElement("span");
                span.className = "search-highlight";
                span.style.backgroundColor = "yellow";
                span.style.padding = "1px";
                
                const beforeText = text.substring(0, index);
                const matchText = text.substring(index, index + query.length);
                const afterText = text.substring(index + query.length);
                
                const beforeNode = document.createTextNode(beforeText);
                const matchNode = document.createTextNode(matchText);
                const afterNode = document.createTextNode(afterText);
                
                span.appendChild(matchNode);
                const parent = node.parentNode;
                parent.insertBefore(beforeNode, node);
                parent.insertBefore(span, node);
                parent.insertBefore(afterNode, node);
                parent.removeChild(node);
                
                break; // 첫 번째 매치만 하이라이트
            }
        }
    }
}
'
    
    # 모든 HTML 파일에 검색 기능 추가
    find "$OUTPUT_DIR/html" -name "*.html" | while read -r html_file; do
        if [[ "$html_file" != "$OUTPUT_DIR/html/index.html" ]]; then
            # 검색 바 추가
            sed -i '/<body>/a\
    <div style="position: fixed; top: 10px; right: 10px; z-index: 1000; background: white; padding: 10px; border: 1px solid #ccc; border-radius: 5px;">\
        <input type="text" id="searchInput" placeholder="문서 검색..." onkeyup="searchDocs()" style="width: 200px; padding: 5px;">\
    </div>' "$html_file" 2>/dev/null || true
            
            # JavaScript 추가
            sed -i '/<\/head>/i\
    <script>'"$search_js"'</script>' "$html_file" 2>/dev/null || true
        fi
    done
    
    log_success "검색 기능 추가 완료"
}

# 문서 통계 생성
generate_doc_stats() {
    log_step "문서 통계 생성 중..."
    
    local stats_file="$OUTPUT_DIR/stats.txt"
    
    {
        echo "UnifiedArch OS 문서 통계"
        echo "======================"
        echo "생성 시간: $(date)"
        echo "버전: $VERSION"
        echo ""
        
        echo "파일 통계:"
        echo "HTML 파일: $(find "$OUTPUT_DIR/html" -name "*.html" | wc -l)"
        echo "PDF 파일: $(find "$OUTPUT_DIR/pdf" -name "*.pdf" | wc -l)"
        echo "매뉴얼 페이지: $(find "$OUTPUT_DIR/man" -name "*.1" | wc -l)"
        echo ""
        
        echo "크기 통계:"
        echo "HTML 총 크기: $(du -sh "$OUTPUT_DIR/html" | cut -f1)"
        echo "PDF 총 크기: $(du -sh "$OUTPUT_DIR/pdf" | cut -f1)"
        echo ""
        
        echo "파일 목록:"
        echo "HTML 파일들:"
        find "$OUTPUT_DIR/html" -name "*.html" | sed 's|.*/||' | sort
        echo ""
        echo "PDF 파일들:"
        find "$OUTPUT_DIR/pdf" -name "*.pdf" | sed 's|.*/||' | sort || echo "없음"
        
    } > "$stats_file"
    
    log_success "문서 통계 생성됨: $stats_file"
}

# 전체 문서 빌드
build_all_docs() {
    log_step "전체 문서 빌드 시작"
    
    # 마크다운 파일 변환
    find "$DOCS_DIR" -name "*.md" | while read -r md_file; do
        local basename=$(basename "$md_file" .md)
        local html_file="$OUTPUT_DIR/html/$basename.html"
        local pdf_file="$OUTPUT_DIR/pdf/$basename.pdf"
        local title=$(grep -m1 "^# " "$md_file" | sed 's/^# //' || echo "$basename")
        
        convert_markdown_to_html "$md_file" "$html_file" "$title"
        convert_markdown_to_pdf "$md_file" "$pdf_file" "$title"
    done
    
    # 추가 문서 생성
    generate_man_pages
    generate_api_docs
    generate_tool_docs
    generate_index
    add_search_functionality
    generate_doc_stats
    
    log_success "전체 문서 빌드 완료"
}

# 도움말 표시
show_help() {
    echo "UnifiedArch OS 문서 생성 시스템"
    echo ""
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  all          - 모든 문서 빌드 (기본)"
    echo "  html         - HTML 문서만 빌드"
    echo "  pdf          - PDF 문서만 빌드"
    echo "  man          - 매뉴얼 페이지만 생성"
    echo "  api          - API 문서만 생성"
    echo "  tools        - 도구 문서만 생성"
    echo "  index        - 인덱스 페이지만 생성"
    echo "  search       - 검색 기능만 추가"
    echo "  stats        - 통계만 생성"
    echo "  clean        - 빌드 파일 정리"
    echo "  serve        - 로컬 서버로 문서 제공"
    echo "  help         - 이 도움말 표시"
}

# 로컬 서버로 문서 제공
serve_docs() {
    local port="${1:-8000}"
    
    log_info "로컬 서버 시작: http://localhost:$port"
    
    if command -v python3 >/dev/null 2>&1; then
        cd "$OUTPUT_DIR/html"
        python3 -m http.server "$port"
    elif command -v python >/dev/null 2>&1; then
        cd "$OUTPUT_DIR/html"
        python -m SimpleHTTPServer "$port"
    else
        log_error "Python이 설치되지 않았습니다"
        exit 1
    fi
}

# 빌드 파일 정리
clean_docs() {
    log_step "문서 빌드 파일 정리 중..."
    
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
        log_info "빌드 디렉토리 정리 완료"
    fi
    
    if [[ -d "$OUTPUT_DIR" ]]; then
        rm -rf "$OUTPUT_DIR"
        log_info "출력 디렉토리 정리 완료"
    fi
    
    log_success "문서 빌드 파일 정리 완료"
}

# 메인 함수
main() {
    local action="${1:-all}"
    
    banner
    
    case "$action" in
        "all")
            check_doc_environment
            build_all_docs
            ;;
        "html")
            check_doc_environment
            find "$DOCS_DIR" -name "*.md" | while read -r md_file; do
                local basename=$(basename "$md_file" .md)
                local html_file="$OUTPUT_DIR/html/$basename.html"
                local title=$(grep -m1 "^# " "$md_file" | sed 's/^# //' || echo "$basename")
                convert_markdown_to_html "$md_file" "$html_file" "$title"
            done
            ;;
        "pdf")
            check_doc_environment
            find "$DOCS_DIR" -name "*.md" | while read -r md_file; do
                local basename=$(basename "$md_file" .md)
                local pdf_file="$OUTPUT_DIR/pdf/$basename.pdf"
                local title=$(grep -m1 "^# " "$md_file" | sed 's/^# //' || echo "$basename")
                convert_markdown_to_pdf "$md_file" "$pdf_file" "$title"
            done
            ;;
        "man")
            generate_man_pages
            ;;
        "api")
            generate_api_docs
            ;;
        "tools")
            generate_tool_docs
            ;;
        "index")
            generate_index
            ;;
        "search")
            add_search_functionality
            ;;
        "stats")
            generate_doc_stats
            ;;
        "serve")
            serve_docs "${2:-8000}"
            ;;
        "clean")
            clean_docs
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "알 수 없는 옵션: $action"
            show_help
            exit 1
            ;;
    esac
}

# 스크립트 실행
main "$@"
