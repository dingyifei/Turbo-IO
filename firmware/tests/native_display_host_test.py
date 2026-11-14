"""Host the production native display page (src/display-runtime-v1/native_display_test.c), Sensors screen included.

It compiles native_display_test.c, which includes the production page (native_display_page.c) so that the Sensors
case can format the all-maximum text with the real code, with the file receiver, display runtime, carrier and client,
render_idle.c and diagnostics.c, with TDP_NATIVE_HOST_TEST, the tree's base flags (tests/host_layout.py), -Werror,
ASan and UBSan, once with the Sensors page's Light line on (TIO_SENSORS_LIGHT=1, the default) and once off (0). The
test stubs the Sensors providers (td_stock_light, td_light_bucket, the IMU byte and the hinge state); native_light.c
itself is hosted by tests/native_light_host_test.py. UBSan and ASan reports fail the run.

  python3 -I firmware/tests/native_display_host_test.py [--out DIR]
"""
from pathlib import Path
import argparse, importlib.util, subprocess, tempfile
FW = Path(__file__).resolve().parents[1]
D = FW/'src'/'display-runtime-v1'
SOURCES = (D/'native_display_test.c', D/'native_display_file.c', D/'display_runtime.c',   # the test includes the page
           D/'display_carrier.c', D/'display_client.c', FW/'src'/'image-upload-test'/'render_idle.c',
           FW/'src'/'diagnostics-v1'/'diagnostics.c')


def host_layout():
    spec = importlib.util.spec_from_file_location('native_display_host_layout', FW/'tests'/'host_layout.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='tmg12-native-display-') as tmp:
        out = args.out or Path(tmp)
        out.mkdir(parents=True, exist_ok=True)
        flags = host_layout().flags()
        for light in ('1', '0'):
            exe = out/('native-display-test-%s' % light)
            subprocess.run(['xcrun', 'clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
                            '-fsanitize=address,undefined', '-fno-sanitize-recover=undefined',
                            '-DTDP_NATIVE_HOST_TEST', '-DTIO_SENSORS_LIGHT=' + light, *flags,
                            '-I', str(D), '-I', str(FW/'src'), *map(str, SOURCES), '-o', str(exe)], check=True)
            subprocess.run([str(exe)], check=True)


if __name__ == '__main__':
    main()
