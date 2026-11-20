#!/usr/bin/env python3
"""Android(APK) 빌드 전처리 (멱등). 저장소 루트에서 실행.

- 단독 실행 (ios_prepare.py 필요 없음)
  1) project.godot : ETC / ETC2 텍스처 임포트 활성화 (Android 필수)
  2) ko-assets/    : 한글 번역/폰트 적용 + 번역 목록에 ko 추가
  3) 태그팀 폰트 이름 맞춤
- export_presets.cfg 는 저장소 것을 쓰지 않고 CI용 Android 프리셋으로 통째로 교체
  (원본은 작성자 PC 경로의 커스텀 템플릿 + 스크립트 암호화 키 + 키스토어 비밀번호가 들어 있어 CI에서 못 씀)
"""
import os
import re
import sys

import shutil


def _read(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return f.read()


def _write(path, text):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def _sub(path, old, new, label):
    """정확히 한 번 나오는 문자열을 바꿈 (이미 적용됐으면 건너뜀)."""
    src = _read(path)
    nl = "\r\n" if "\r\n" in src else "\n"
    old = old.replace("\n", nl)
    new = new.replace("\n", nl)
    if new in src:
        print(f"[skip] {path}: {label} (이미 적용됨)")
        return
    if src.count(old) != 1:
        print(f"[warn] {path}: {label} 위치를 찾지 못함 ({src.count(old)}곳)")
        return
    _write(path, src.replace(old, new))
    print(f"[ok]   {path}: {label}")


def apply_korean():
    root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ko-assets"))
    if not os.path.isdir(root):
        print("[skip] ko-assets/ 없음 (한국어 미적용)")
        return
    n = 0
    for base, _, files in os.walk(root):
        for name in files:
            src = os.path.join(base, name)
            rel = os.path.relpath(src, root)
            os.makedirs(os.path.dirname(rel) or ".", exist_ok=True)
            shutil.copyfile(src, rel)
            n += 1
    print(f"[ok]   ko-assets: {n}개 파일 복사")
    src = _read("project.godot")
    ko = "res://src/Localization/real_translations.ko.translation"
    if ko in src:
        print("[skip] project.godot (ko 번역 이미 등록됨)")
        return
    m = re.search(r"(translations=PoolStringArray\()(.*?)(\s*\))", src, re.S)
    if not m:
        sys.exit("[error] project.godot에서 locale/translations 목록을 찾지 못함")
    body = m.group(2).rstrip()
    new = body + ', "' + ko + '"' if body.strip() else '"' + ko + '"'
    _write("project.godot", src[: m.start(2)] + new + src[m.end(2):])
    print("[ok]   project.godot += ko 번역")


def patch_fonts():
    """옛 폰트 파일명(Xclassicfont/X8bitmapfont)에도 한글 비트맵 폰트를 복사하고 menuFont 높이를 맞춤."""
    fonts = "src/Fonts"
    for src_name, dst_name in [("xclassicfontfinal.fnt", "Xclassicfont.fnt"),
                               ("x8bitmapfontfinal.fnt", "X8bitmapfont.fnt")]:
        src = os.path.join(fonts, src_name)
        if not os.path.exists(src):
            print(f"[warn] {src} 없음")
            continue
        shutil.copyfile(src, os.path.join(fonts, dst_name))
        print(f"[ok]   {dst_name} <- {src_name}")
    menu = os.path.join(fonts, "menuFont.tres")
    if os.path.exists(menu):
        _sub(menu, "height = 8.0\n", "height = 14.0\n", "menuFont 높이 8 -> 14")


PACKAGE = os.environ.get("ANDROID_PACKAGE", "com.mmx8.teamtag.AND")
VERSION_NAME = os.environ.get("VERSION_NAME", "0.9.1")
VERSION_CODE = os.environ.get("VERSION_CODE", "1")

PRESET = """[preset.0]

name="Android"
platform="Android"
runnable=true
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="*.ase, *.aseprite, *.pdn, *.csv, *.txt, *.md, *.zip, *.dll, *.exe, *.ico, *.gif, *.world"
export_path=""
script_export_mode=1
script_encryption_key=""

[preset.0.options]

custom_template/debug=""
custom_template/release=""
custom_build/use_custom_build=false
architectures/armeabi-v7a=true
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
keystore/debug=""
keystore/debug_user=""
keystore/debug_password=""
keystore/release=""
keystore/release_user=""
keystore/release_password=""
one_click_deploy/clear_previous_install=false
version/code={code}
version/name="{vname}"
package/unique_name="{pkg}"
package/name="MMX8 Zashiko-Mod"
package/signed=true
package/classify_as_game=true
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
launcher_icons/main_192x192=""
launcher_icons/adaptive_foreground_432x432=""
launcher_icons/adaptive_background_432x432=""
graphics/opengl_debug=false
xr_features/xr_mode=0
screen/immersive_mode=true
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
user_data_backup/allow=false
command_line/extra_args=""
apk_expansion/enable=false
permissions/custom_permissions=PoolStringArray(  )
permissions/internet=false
permissions/vibrate=true
permissions/write_external_storage=false
"""


def patch_project_godot_android():
    path = "project.godot"
    src = _read(path)
    nl = "\r\n" if "\r\n" in src else "\n"
    m = re.search(r"^\[rendering\]\s*$", src, re.M)
    if not m:
        sys.exit("[error] project.godot에 [rendering] 섹션이 없음")
    want = ["vram_compression/import_etc=true", "vram_compression/import_etc2=true"]
    add = [w for w in want if not re.search(r"^" + re.escape(w.split("=")[0]) + r"=", src, re.M)]
    if not add:
        print("[skip] project.godot (ETC 이미 설정됨)")
        return
    src = src[:m.end()] + nl + nl.join(add) + src[m.end():]
    _write(path, src)
    print(f"[ok]   project.godot += {add}")


def write_preset():
    text = PRESET.format(code=VERSION_CODE, vname=VERSION_NAME, pkg=PACKAGE)
    _write("export_presets.cfg", text)
    print("[ok]   export_presets.cfg 를 Android CI 프리셋으로 교체")


if __name__ == "__main__":
    if not os.path.exists("project.godot"):
        sys.exit("[error] 저장소 루트(project.godot가 있는 곳)에서 실행하세요")
    patch_project_godot_android()
    apply_korean()
    patch_fonts()
    write_preset()
