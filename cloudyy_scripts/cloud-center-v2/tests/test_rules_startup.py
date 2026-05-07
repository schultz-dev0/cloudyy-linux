import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from lib.rules_startup_page import WindowRule, LayerRule, AutostartEntry, EnvVar, _parse_window_rules, _serialize_window_rules


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
