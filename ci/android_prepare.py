#!/usr/bin/env python3
"""안드로이드 APK 빌드용 소스 전처리 (저장소 루트에서 실행: python3 ci/android_prepare.py)

- ios_prepare.py 의 '공통' 패치(한글, 폰트/글자 위치, 불러오기 슬롯 등)는 그대로 가져다 쓴다.
- iOS 전용 패치(가상패드 오버레이, 안드로이드 터치 UI 삭제, is_Android 변경 등)는 쓰지 않는다.
  (안드로이드는 게임에 원래 들어있는 터치 UI(System/Android)와 OS.get_name() == "Android" 를 그대로 쓴다)
- iOS 용으로 빼 둔 안드로이드 전용 화면(터치 키 설정 메뉴, 안드로이드 컨트롤 옵션)은
  android-assets/ 에 있는 파일로 되살린다 (RESTORE_ANDROID_UI=0 이면 안 함).

환경 변수(워크플로가 넣어 줌): ANDROID_PACKAGE, APP_DISPLAY_NAME, VERSION_CODE, VERSION_NAME,
KEYSTORE_PATH, KEYSTORE_USER, KEYSTORE_PASS, RESTORE_ANDROID_UI
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ios_prepare as ip  # read/write/_sub 와 공통 패치를 재사용 (import 만으로는 아무것도 실행되지 않음)

PRESET_NAME = "Android CI"
PACKAGE = os.environ.get("ANDROID_PACKAGE") or "com.mmx8.allinone.android"
APP_NAME = os.environ.get("APP_DISPLAY_NAME") or "MMX8 AIO MOD"
VERSION_CODE = os.environ.get("VERSION_CODE") or "1"
VERSION_NAME = os.environ.get("VERSION_NAME") or "1.0.0"
KEYSTORE = os.environ.get("KEYSTORE_PATH") or ""
KEYSTORE_USER = os.environ.get("KEYSTORE_USER") or "mmx8"
KEYSTORE_PASS = os.environ.get("KEYSTORE_PASS") or "android"
RESTORE_ANDROID_UI = (os.environ.get("RESTORE_ANDROID_UI") or "1").strip().lower() not in ("0", "false", "no", "off")


def apply_android_assets():
    """iOS 쪽 소스에서 지워 둔 안드로이드 전용 화면/옵션을 되살린다 (android-assets/ 를 저장소 위에 덮어씀)."""
    if not RESTORE_ANDROID_UI:
        print("[skip] android-assets (RESTORE_ANDROID_UI=0: 안드로이드 전용 메뉴 되살리지 않음)")
        return
    root = os.path.normpath(os.path.join(HERE, "..", "android-assets"))
    if not os.path.isdir(root):
        print("[warn] android-assets/ 없음 - 안드로이드 전용 메뉴를 되살리지 못함")
        return
    n = 0
    for base, _, files in os.walk(root):
        for name in files:
            src = os.path.join(base, name)
            rel = os.path.relpath(src, root)
            os.makedirs(os.path.dirname(rel) or ".", exist_ok=True)
            shutil.copyfile(src, rel)
            n += 1
    print(f"[ok]   android-assets: {n}개 파일 복사 (안드로이드 전용 메뉴 되살림)")


def patch_project_android():
    """안드로이드 내보내기에 필요한 텍스처 압축(ETC/ETC2)을 켠다."""
    path = "project.godot"
    src = ip.read(path)
    nl = "\r\n" if "\r\n" in src else "\n"
    if not re.search(r"^\[rendering\]\s*$", src, re.M):
        sys.exit("[error] project.godot에 [rendering] 섹션이 없음")
    changed = []
    for key in ("vram_compression/import_etc", "vram_compression/import_etc2"):
        line = re.compile(r"^" + re.escape(key) + r"=.*$", re.M)
        if line.search(src):
            if not re.search(r"^" + re.escape(key) + r"=true\s*$", src, re.M):
                src = line.sub(key + "=true", src, count=1)
                changed.append(key)
        else:
            m = re.search(r"^\[rendering\]\s*$", src, re.M)
            src = src[: m.end()] + nl + key + "=true" + src[m.end():]
            changed.append(key)
    if not changed:
        print("[skip] project.godot (ETC/ETC2 이미 켜짐)")
        return
    ip.write(path, src)
    print(f"[ok]   project.godot += {changed}")


def _set_value(text, key, value):
    """프리셋 블록 안의 'key=값' 줄을 통째로 바꾼다 (줄바꿈 형식 유지)."""
    pat = re.compile(r"^" + re.escape(key) + r"=.*?(\r?)$", re.M)
    if not pat.search(text):
        print(f"[warn] 프리셋에 {key} 항목이 없어 건너뜀")
        return text
    return pat.sub(lambda m: f"{key}={value}{m.group(1)}", text, count=1)


def patch_presets_android():
    """기존 'Android (test)' 프리셋을 복사해서 CI 용 프리셋을 하나 더 만든다.
    (원본 프리셋은 작성자 PC 의 커스텀 엔진/키스토어 경로를 가리켜서 그대로는 못 씀)"""
    path = "export_presets.cfg"
    src = ip.read(path)
    if re.search(r'^name="' + re.escape(PRESET_NAME) + r'"', src, re.M):
        print(f"[skip] export_presets.cfg ({PRESET_NAME} 프리셋 이미 있음)")
        return
    nl = "\r\n" if "\r\n" in src else "\n"
    parts = re.split(r"^(?=\[preset\.\d+\]\r?$)", src, flags=re.M)
    cands = [p for p in parts if re.match(r"\[preset\.\d+\]", p) and re.search(r'^platform="Android"', p, re.M)]
    if not cands:
        sys.exit("[error] export_presets.cfg 에 Android 프리셋이 없음")
    base = next((p for p in cands if 'name="Android (test)"' in p), cands[0])
    nums = [int(x) for x in re.findall(r"^\[preset\.(\d+)\]", src, re.M)]
    n = max(nums) + 1
    old_n = int(re.match(r"\[preset\.(\d+)\]", base).group(1))
    blk = base.replace(f"[preset.{old_n}]", f"[preset.{n}]", 1)
    blk = blk.replace(f"[preset.{old_n}.options]", f"[preset.{n}.options]", 1)

    q = lambda s: '"' + s.replace('"', '\\"') + '"'
    for key, val in [
        ("name", q(PRESET_NAME)),
        ("runnable", "false"),
        ("export_path", q("")),
        # 원래 제외 목록(*.csv, *.txt, *.pdn)에 빌드용 파일/서명 키가 APK 안에 들어가지 않도록 추가
        ("exclude_filter", q("*.csv, *.txt, *.pdn, *.ase, *.aseprite, *.py, *.md, *.zip, *.dll, *.exe, *.ico, *.world, *.keystore, *.jks, *.apk, *.aab, *.tpz, res://build/*, res://Godot.app/*, res://tpl/*")),
        ("custom_template/debug", q("")),
        ("custom_template/release", q("")),
        ("custom_build/use_custom_build", "false"),
        ("architectures/armeabi-v7a", "true"),
        ("architectures/arm64-v8a", "true"),
        ("architectures/x86", "false"),
        ("architectures/x86_64", "false"),
        ("keystore/debug", q("")),
        ("keystore/debug_user", q("")),
        ("keystore/debug_password", q("")),
        ("keystore/release", q(KEYSTORE)),
        ("keystore/release_user", q(KEYSTORE_USER)),
        ("keystore/release_password", q(KEYSTORE_PASS)),
        ("version/code", VERSION_CODE),
        ("version/name", q(VERSION_NAME)),
        ("package/unique_name", q(PACKAGE)),
        ("package/name", q(APP_NAME)),
    ]:
        blk = _set_value(blk, key, val)
    if not KEYSTORE:
        print("[warn] KEYSTORE_PATH 가 비어 있음 - 릴리스 서명이 안 돼서 내보내기가 실패할 수 있음")

    ip.write(path, src.rstrip() + nl + nl + blk.strip("\r\n") + nl)
    print(f"[ok]   export_presets.cfg += preset.{n} ({PRESET_NAME}, {PACKAGE}, v{VERSION_NAME}/{VERSION_CODE})")


# 가상패드 자동 숨김: 물리 버튼/블루투스 패드로 조작 중이면 화면의 가상패드(System/Android)를 숨긴다.
#  - 패드가 연결돼 있으면 계속 숨김 (지문 센서 같은 가짜 패드는 제외)
#  - 연결된 패드가 없어도 키/패드 버튼 입력이 들어오면(안드로이드 게임기의 내장 버튼 등) 숨김
#  - 그 상태에서 화면을 터치하면 다시 보여줌 (패드 연결 중에는 계속 숨김)
TOUCH_AUTO_PATH = "System/Android/TouchAuto.gd"
TOUCH_AUTO_GD = """extends Node
# 물리 버튼/블루투스 패드로 조작 중이면 화면의 가상패드를 숨기고, 화면을 터치하면 다시 보여준다

const EXCLUDED_PADS = ["uinput-fpc", "uinput-fortsense", "uinput-hidraw"]
const IGNORED_KEYS = [KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_VOLUMEMUTE]

var pad_connected: bool = false
var physical_input: bool = false
var hidden_now: bool = false
var roots: Array = []


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	pad_connected = _any_real_pad()
	hidden_now = pad_connected
	var _e1 = Input.connect("joy_connection_changed", self, "_on_joy_connection_changed")
	var _e2 = get_tree().connect("node_added", self, "_on_node_added")


func _is_excluded(device: int) -> bool:
	var pad_name: String = Input.get_joy_name(device)
	for x in EXCLUDED_PADS:
		if pad_name.begins_with(x):
			return true
	return false


func _any_real_pad() -> bool:
	for id in Input.get_connected_joypads():
		if not _is_excluded(id):
			return true
	return false


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	pad_connected = _any_real_pad()
	_apply()


func _on_node_added(n: Node) -> void:
	if n is TouchScreenButton and not (n.get_parent() is TouchScreenButton):
		roots.append(n)
		call_deferred("_apply_node", n)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and physical_input:
			physical_input = false
			_apply()
	elif event is InputEventJoypadButton:
		if event.pressed and not physical_input and not _is_excluded(event.device):
			physical_input = true
			_apply()
	elif event is InputEventJoypadMotion:
		if abs(event.axis_value) > 0.6 and not physical_input and not _is_excluded(event.device):
			physical_input = true
			_apply()
	elif event is InputEventKey:
		if event.pressed and not event.echo and not (event.scancode in IGNORED_KEYS) and not physical_input:
			physical_input = true
			_apply()


func _apply() -> void:
	hidden_now = pad_connected or physical_input
	var keep: Array = []
	for n in roots:
		if is_instance_valid(n):
			keep.append(n)
			_apply_node(n)
	roots = keep


func _apply_node(n) -> void:
	if not is_instance_valid(n):
		return
	if hidden_now:
		if not n.has_meta("ta_hidden"):
			n.set_meta("ta_vis", n.visible)
			n.set_meta("ta_hidden", true)
		n.visible = false
	elif n.has_meta("ta_hidden"):
		n.visible = n.get_meta("ta_vis")
		n.remove_meta("ta_hidden")
"""

# 조이스틱류(Area2D)는 숨겨도 _input 이 계속 돌기 때문에, 보이지 않을 때는 입력을 무시하고 눌린 방향을 풀어 준다
TOUCH_GUARD_FILES = ["System/Android/joystick.gd", "System/Android/weaponround.gd"]
TOUCH_GUARD_MARK = "# Android-PORT: 가상패드 숨김 중에는 입력 무시"


def patch_touch_auto():
    # 1) 자동 숨김 스크립트 추가
    if os.path.exists(TOUCH_AUTO_PATH) and "ta_hidden" in ip.read(TOUCH_AUTO_PATH):
        print(f"[skip] {TOUCH_AUTO_PATH} (이미 있음)")
    else:
        ip.write(TOUCH_AUTO_PATH, TOUCH_AUTO_GD)
        print(f"[ok]   {TOUCH_AUTO_PATH} 추가 (가상패드 자동 숨김)")

    # 2) project.godot autoload 등록
    path = "project.godot"
    src = ip.read(path)
    if "TouchAuto=" in src:
        print("[skip] project.godot (TouchAuto 이미 등록됨)")
    else:
        nl = "\r\n" if "\r\n" in src else "\n"
        m = re.search(r"^\[autoload\]\r?\n", src, re.M)
        if not m:
            print("[warn] project.godot 에 [autoload] 섹션이 없음")
        else:
            end = re.search(r"^\r?\n", src[m.end():], re.M)
            at = m.end() + (end.start() if end else len(src) - m.end())
            src = src[:at] + 'TouchAuto="*res://System/Android/TouchAuto.gd"' + nl + src[at:]
            ip.write(path, src)
            print("[ok]   project.godot += TouchAuto autoload")

    # 3) 조이스틱/무기 링: 숨김 중에는 입력 무시
    for f in TOUCH_GUARD_FILES:
        if not os.path.exists(f):
            print(f"[warn] {f} 없음 - 건너뜀")
            continue
        src = ip.read(f)
        if TOUCH_GUARD_MARK in src:
            print(f"[skip] {f} (이미 패치됨)")
            continue
        nl = "\r\n" if "\r\n" in src else "\n"
        m = re.search(r"^func _input\(event\):\r?\n", src, re.M)
        if not m:
            print(f"[warn] {f}: _input 을 찾지 못함 - 건너뜀")
            continue
        guard = nl.join([
            "\t" + TOUCH_GUARD_MARK,
            "\tif not is_visible_in_tree():",
            "\t\tif touch_id != null:",
            "\t\t\ttouch_id = null",
            "\t\t\treset_joystick()",
            "\t\treturn",
            "",
        ])
        ip.write(f, src[:m.end()] + guard + src[m.end():])
        print(f"[ok]   {f}: 숨김 중에는 입력 무시")


def _run(name):
    """ios_prepare.py 의 공통 패치를 이름으로 실행. 그 파일에 없는 함수면 경고만 하고 건너뛴다
    (iOS 저장소의 최신 ci/ios_prepare.py 를 이 저장소의 ci/ 로 복사해 오면 전부 적용됨)."""
    fn = getattr(ip, name, None)
    if fn is None:
        print(f"[warn] ios_prepare.py 에 {name}() 가 없어 건너뜀 - iOS 저장소의 최신 ci/ios_prepare.py 로 교체하면 적용됨")
        return
    fn()


if __name__ == "__main__":
    if not os.path.exists("project.godot"):
        sys.exit("[error] 저장소 루트(project.godot가 있는 곳)에서 실행하세요")
    # 1) 안드로이드 전용 화면 되살리기 + 내보내기 설정
    apply_android_assets()
    patch_project_android()
    patch_touch_auto()
    patch_presets_android()
    # 2) 공통 패치 (iOS 빌드와 같은 순서)
    _run("patch_spawner")
    _run("patch_loading_slot_menu")
    _run("patch_title_version_text")
    _run("patch_save_version")
    _run("patch_clear_color")
    _run("apply_korean")
    _run("patch_ko_extra")
    _run("patch_languages")
    _run("patch_tagteam_fonts")
    _run("patch_tagteam_layout")
    print("[done] 안드로이드 전처리 완료")
