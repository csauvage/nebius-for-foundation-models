#!/usr/bin/env python3
"""Verify auth diagnostics exported to downstream Swift clients in Debug and Release.

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tools/verify_release_auth_warnings.py
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MARKERS = [
    'Release build: direct Nebius API-key authentication.',
    'Release build: direct Tavily API-key authentication.',
    'Release build: direct Nebius management API-key authentication.',
]
IMPORTS = 'import NebiusAPI\nimport NebiusForFoundationModels\nimport TavilyAPI\n'
DIRECT = IMPORTS + '''
func directAuthentication() throws {
  let _: NebiusAuth = .apiKey("test-only")
  let _: TavilyAuth = .apiKey("test-only")
  _ = try NebiusClient(directAPIKey: "test-only")
}
'''
PROXY = IMPORTS + '''
func proxyAuthentication() throws {
  let _: NebiusAuth = .proxied(headers: ["Authorization": "Bearer test-only"])
  let _: TavilyAuth = .proxied(headers: ["Authorization": "Bearer test-only"])
  _ = try NebiusClient(headers: ["Authorization": "Bearer test-only"])
}
'''


def run(args):
    return subprocess.run(args, cwd=ROOT, text=True, capture_output=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch-path', default='/private/tmp/nebius-release-auth-verification')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='nebius-auth-client-') as fixture_dir:
        fixtures = {}
        for name, content in [('direct', DIRECT), ('proxy', PROXY)]:
            fixture = Path(fixture_dir) / (name + '.swift')
            fixture.write_text(content)
            fixtures[name] = fixture
        for configuration in ['debug', 'release']:
            command = ['xcrun', 'swift', 'build', '--scratch-path', args.scratch_path, '-c', configuration]
            for target in ['NebiusForFoundationModels', 'TavilyAPI']:
                result = run(command + ['--target', target])
                if result.returncode:
                    raise SystemExit(result.stdout + result.stderr)
            result = run(command + ['--show-bin-path'])
            if result.returncode:
                raise SystemExit(result.stdout + result.stderr)
            products = Path(result.stdout.strip())
            modules = products if (products / 'NebiusAPI.swiftmodule').exists() else products / 'Modules'
            for name, fixture in fixtures.items():
                for strict in [False, True]:
                    result = run(['xcrun', 'swiftc', '-typecheck', '-I', str(modules)]
                                 + (['-warnings-as-errors'] if strict else []) + [str(fixture)])
                    expects_warning = configuration == 'release' and name == 'direct'
                    expected_failure = expects_warning and strict
                    output = result.stdout + result.stderr
                    if (result.returncode != 0) != expected_failure:
                        raise SystemExit(f'{configuration}/{name}/strict={strict}: unexpected result\n{output}')
                    for marker in MARKERS:
                        if (marker in output) != expects_warning:
                            raise SystemExit(f'{configuration}/{name}: incorrect diagnostic for {marker}\n{output}')
                    if not expects_warning and ('warning:' in output or 'error:' in output):
                        raise SystemExit(output)
            print(f'PASS {configuration}: downstream direct/proxy authentication, warnings and warnings-as-errors')


if __name__ == '__main__':
    main()
