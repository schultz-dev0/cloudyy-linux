import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from lib.rules_startup_page import WindowRule, LayerRule, AutostartEntry, EnvVar


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
