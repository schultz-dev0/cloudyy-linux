import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from lib.rules_startup_page import WindowRule, LayerRule, AutostartEntry, EnvVar, _parse_window_rules, _serialize_window_rules, _parse_layer_rules, _serialize_layer_rules


def test_window_rule_equality():
    r1 = WindowRule(name='test', matchers=[('match:class', '^(zen)$')], effects={'float': 'on'})
    r2 = WindowRule(name='test', matchers=[('match:class', '^(zen)$')], effects={'float': 'on'})
    assert r1 == r2


def test_window_rule_inequality():
    r1 = WindowRule(name='a', matchers=[('match:class', '^(zen)$')], effects={'float': 'on'})
    r2 = WindowRule(name='b', matchers=[('match:class', '^(zen)$')], effects={'float': 'on'})
    assert r1 != r2


def test_layer_rule_equality():
    r = LayerRule(name='panel', namespace='^(waybar)$', effects={'blur': 'on'})
    assert r == LayerRule(name='panel', namespace='^(waybar)$', effects={'blur': 'on'})


def test_autostart_equality():
    a = AutostartEntry(command='waybar', exec_once=True)
    assert a == AutostartEntry(command='waybar', exec_once=True)
    assert a != AutostartEntry(command='waybar', exec_once=False)


def test_env_var_equality():
    e = EnvVar(name='XCURSOR_THEME', value='Bibata')
    assert e == EnvVar(name='XCURSOR_THEME', value='Bibata')
    assert e != EnvVar(name='XCURSOR_SIZE', value='24')


def test_parse_window_rule_basic():
    lines = [
        'windowrule {',
        '    name        = zen-browser',
        '    match:class = ^(zen)$',
        '    float       = on',
        '    size        = 1080 1080',
        '}',
    ]
    rules = _parse_window_rules(lines)
    assert len(rules) == 1
    r = rules[0]
    assert r.name == 'zen-browser'
    assert r.matchers == [('match:class', '^(zen)$')]
    assert r.effects == {'float': 'on', 'size': '1080 1080'}


def test_parse_window_rule_multi_matcher():
    lines = [
        'windowrule {',
        '    match:class = ^(firefox)$',
        '    match:title = .*Youtube.*',
        '    opaque      = on',
        '}',
    ]
    rules = _parse_window_rules(lines)
    assert rules[0].matchers == [('match:class', '^(firefox)$'), ('match:title', '.*Youtube.*')]


def test_parse_window_rule_no_name():
    lines = ['windowrule {', '    match:class = ^(kitty)$', '    float = on', '}']
    assert _parse_window_rules(lines)[0].name == ''


def test_parse_window_rule_multiple():
    lines = [
        'windowrule {', '    name = a', '    match:class = ^(a)$', '    float = on', '}', '',
        'windowrule {', '    name = b', '    match:class = ^(b)$', '    center = on', '}',
    ]
    rules = _parse_window_rules(lines)
    assert len(rules) == 2
    assert rules[0].name == 'a'
    assert rules[1].name == 'b'


def test_serialize_window_rule_round_trip():
    original = [WindowRule(
        name='zen-browser',
        matchers=[('match:class', '^(zen)$')],
        effects={'float': 'on', 'size': '1080 1080'},
    )]
    assert _parse_window_rules(_serialize_window_rules(original)) == original


def test_serialize_window_rule_no_name_omits_name_key():
    rule = WindowRule(name='', matchers=[('match:class', '^(x)$')], effects={'float': 'on'})
    lines = _serialize_window_rules([rule])
    assert not any('name' in l for l in lines)
    assert _parse_window_rules(lines)[0].matchers == rule.matchers


def test_parse_layer_rule_basic():
    lines = [
        'layerrule {',
        '    name            = quickshell_panel',
        '    match:namespace = ^(quickshell)$',
        '    blur            = on',
        '    ignore_alpha    = 0.2',
        '}',
    ]
    r = _parse_layer_rules(lines)[0]
    assert r.name == 'quickshell_panel'
    assert r.namespace == '^(quickshell)$'
    assert r.effects == {'blur': 'on', 'ignore_alpha': '0.2'}


def test_parse_layer_rule_no_name():
    lines = ['layerrule {', '    match:namespace = rofi', '    blur = on', '}']
    r = _parse_layer_rules(lines)[0]
    assert r.name == ''
    assert r.namespace == 'rofi'


def test_serialize_layer_rule_round_trip():
    original = [LayerRule(
        name='panel', namespace='^(quickshell)$', effects={'blur': 'on', 'ignore_alpha': '0.2'},
    )]
    assert _parse_layer_rules(_serialize_layer_rules(original)) == original


# New tests for autostart and env vars
from lib.rules_startup_page import (
    _parse_autostart, _serialize_autostart,
    _parse_env_vars, _serialize_env_vars,
    _valid_env_name,
)


def test_parse_autostart_exec_once():
    entries = _parse_autostart(['exec-once = waybar', 'exec-once = hyprpaper'])
    assert entries == [
        AutostartEntry(command='waybar', exec_once=True),
        AutostartEntry(command='hyprpaper', exec_once=True),
    ]


def test_parse_autostart_exec():
    entries = _parse_autostart(['exec = some-daemon'])
    assert entries[0] == AutostartEntry(command='some-daemon', exec_once=False)


def test_parse_autostart_mixed():
    entries = _parse_autostart(['exec-once = a', 'exec = b', 'exec-once = c'])
    assert [e.exec_once for e in entries] == [True, False, True]
    assert [e.command for e in entries] == ['a', 'b', 'c']


def test_serialize_autostart_round_trip():
    original = [AutostartEntry('waybar', True), AutostartEntry('daemon', False)]
    assert _parse_autostart(_serialize_autostart(original)) == original


def test_parse_env_var_basic():
    vars_ = _parse_env_vars(['env = XCURSOR_THEME,Bibata-Modern-Ice', 'env = XCURSOR_SIZE,24'])
    assert vars_[0] == EnvVar(name='XCURSOR_THEME', value='Bibata-Modern-Ice')
    assert vars_[1] == EnvVar(name='XCURSOR_SIZE', value='24')


def test_parse_env_var_comma_in_value():
    vars_ = _parse_env_vars(['env = MY_VAR,a,b,c'])
    assert vars_[0] == EnvVar(name='MY_VAR', value='a,b,c')


def test_serialize_env_var_round_trip():
    original = [EnvVar('FOO', 'bar'), EnvVar('BAZ', '1,2,3')]
    assert _parse_env_vars(_serialize_env_vars(original)) == original


def test_valid_env_name():
    assert _valid_env_name('XCURSOR_THEME')
    assert _valid_env_name('_FOO')
    assert _valid_env_name('foo123')
    assert not _valid_env_name('')
    assert not _valid_env_name('123BAD')
    assert not _valid_env_name('HAS SPACE')
    assert not _valid_env_name('HAS-DASH')


# Conf file I/O tests
import tempfile
from pathlib import Path
from lib.rules_startup_page import _parse_conf, _write_conf

_SAMPLE_CONF = """\
# --- CC: Window Rules ---
windowrule {
    name        = zen-browser
    match:class = ^(zen)$
    float       = on
}
# --- CC: End Window Rules ---

# --- CC: Layer Rules ---
layerrule {
    name            = panel
    match:namespace = ^(waybar)$
    blur            = on
}
# --- CC: End Layer Rules ---

# --- CC: Autostart ---
exec-once = waybar
# --- CC: End Autostart ---

# --- CC: Environment ---
env = XCURSOR_THEME,Bibata
# --- CC: End Environment ---
"""


def test_parse_conf_sections():
    s = _parse_conf(_SAMPLE_CONF)
    assert any('zen-browser' in l for l in s['window_rules'])
    assert any('waybar' in l for l in s['layer_rules'])
    assert any('exec-once = waybar' in l for l in s['autostart'])
    assert any('XCURSOR_THEME' in l for l in s['env_vars'])


def test_parse_conf_empty():
    assert _parse_conf('') == {k: [] for k in ('window_rules', 'layer_rules', 'autostart', 'env_vars')}


def test_write_conf_round_trip():
    window_rules = [WindowRule('test', [('match:class', '^(x)$')], {'float': 'on'})]
    layer_rules  = [LayerRule('l', 'rofi', {'blur': 'on'})]
    autostart    = [AutostartEntry('waybar', True)]
    env_vars     = [EnvVar('FOO', 'bar')]

    with tempfile.NamedTemporaryFile(suffix='.conf', delete=False) as f:
        tmp = Path(f.name)
    try:
        _write_conf(window_rules, layer_rules, autostart, env_vars, path=tmp)
        s = _parse_conf(tmp.read_text())
        assert _parse_window_rules(s['window_rules']) == window_rules
        assert _parse_layer_rules(s['layer_rules'])   == layer_rules
        assert _parse_autostart(s['autostart'])        == autostart
        assert _parse_env_vars(s['env_vars'])          == env_vars
    finally:
        tmp.unlink(missing_ok=True)
