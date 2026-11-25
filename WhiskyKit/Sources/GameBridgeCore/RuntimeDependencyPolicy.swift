// SPDX-License-Identifier: GPL-3.0-or-later

/// Identifies runtime families from a PE import name; detection is not proof of absence.
public enum RuntimeDependencyPolicy {
    public static func component(for name: String) -> String? {
        guard name.lowercased().hasSuffix(".dll") else { return nil }
        let families = [
            ("80", "2005"), ("90", "2008"), ("100", "2010"), ("110", "2012"), ("120", "2013"), ("140", "v14")
        ]
        let prefixes = ["msvcr", "msvcp", "msvcm", "mfc", "mfcm", "atl", "vcomp", "vcruntime", "concrt", "vccorlib"]
        let basename = String(name.lowercased().dropLast(4))
        let family = families.first { version, _ in
            prefixes.contains { prefix in
                let stem = prefix + version
                return basename == stem || basename == stem + "u" || basename.hasPrefix(stem + "_")
            }
        }
        if let family { return "Visual C++ " + family.1 }
        if ["d3dx9_", "d3dx10_", "d3dx11_", "xactengine", "x3daudio1_"].contains(where: basename.hasPrefix)
            || ["xinput1_3", "xaudio2_7", "d3dcompiler_43"].contains(basename) {
            return "DirectX June 2010"
        }
        if basename == "mscoree" { return ".NET Framework" }
        if ["openal32", "wrap_oal"].contains(basename) { return "OpenAL" }
        if ["physxloader", "physxloader64", "physxcore"].contains(basename) { return "PhysX" }
        if basename.hasPrefix("microsoft.xna.framework") { return "XNA Framework" }
        return nil
    }
}
