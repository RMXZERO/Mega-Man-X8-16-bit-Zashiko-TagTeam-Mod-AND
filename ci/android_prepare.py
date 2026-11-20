#!/usr/bin/env python3
"""Android(APK) 빌드 전처리 (멱등). 저장소 루트에서 실행.

- ios_prepare.py 의 공용 패치를 재사용 (iOS 전용 패치는 쓰지 않음)
  1) project.godot : ETC / ETC2 텍스처 임포트 활성화 (Android 필수)
  2) ko-assets/    : 한글 번역/폰트 적용 + 번역 목록에 ko 추가
  3) 태그팀 폰트 이름 맞춤
- export_presets.cfg 는 저장소 것을 쓰지 않고 CI용 Android 프리셋으로 통째로 교체
  (원본은 작성자 PC 경로의 커스텀 템플릿 + 스크립트 암호화 키 + 키스토어 비밀번호가 들어 있어 CI에서 못 씀)
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ios_prepare as p  # __main__ 가드가 있어 import 만으로는 실행되지 않음

PACKAGE = os.environ.get("ANDROID_PACKAGE", "com.mmx8.zashiko")
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
    src = p.read(path)
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
    p.write(path, src)
    print(f"[ok]   project.godot += {add}")


def write_preset():
    text = PRESET.format(code=VERSION_CODE, vname=VERSION_NAME, pkg=PACKAGE)
    p.write("export_presets.cfg", text)
    print("[ok]   export_presets.cfg 를 Android CI 프리셋으로 교체")


if __name__ == "__main__":
    if not os.path.exists("project.godot"):
        sys.exit("[error] 저장소 루트(project.godot가 있는 곳)에서 실행하세요")
    patch_project_godot_android()
    p.apply_korean()
    p.patch_tagteam_fonts()
    write_preset()
