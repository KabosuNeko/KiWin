using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;

namespace KiWin.Core;

public static class AppPaths
{
    public const string BundleResourceName = "appbundle.zip";
    private const string DataDirName = "KiWin";
    private const string ExtractDirName = "appdata";
    private const string StampFileName = ".stamp";

    private static string? _dataRoot;
    private static bool _bundleAvailable;

    public static bool BundleAvailable => _bundleAvailable;

    public static string DataRoot()
    {
        if (_dataRoot is not null) return _dataRoot;
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _dataRoot = Path.Combine(
            string.IsNullOrEmpty(local) ? Path.GetTempPath() : local,
            DataDirName);
        return _dataRoot;
    }

    public static string AppDataDir() => Path.Combine(DataRoot(), ExtractDirName);

    public static string Resolve(string relativePath)
        => Path.Combine(AppDataDir(), NormalizeRelative(relativePath));

    public static bool EnsureExtracted()
    {
        try
        {
            var asm = Assembly.GetEntryAssembly() ?? typeof(AppPaths).Assembly;
            using var stream = asm.GetManifestResourceStream(BundleResourceName);
            if (stream is null) return false;

            var hash = ComputeSha256(stream);
            var dataRoot = DataRoot();
            var stampFile = Path.Combine(dataRoot, StampFileName);
            if (File.Exists(stampFile) && File.ReadAllText(stampFile) == hash)
            {
                _bundleAvailable = true;
                return true;
            }

            var target = AppDataDir();
            if (Directory.Exists(target)) Directory.Delete(target, recursive: true);
            Directory.CreateDirectory(target);

            stream.Position = 0;
            using (var zip = new ZipArchive(stream, ZipArchiveMode.Read, leaveOpen: false))
            {
                foreach (var entry in zip.Entries)
                {
                    var rel = NormalizeRelative(entry.FullName);
                    if (rel.Length == 0) continue;
                    var dest = Path.Combine(target, rel);
                    if (entry.FullName.EndsWith("/") || entry.Name.Length == 0)
                    {
                        Directory.CreateDirectory(dest);
                        continue;
                    }
                    Directory.CreateDirectory(Path.GetDirectoryName(dest) ?? target);
                    entry.ExtractToFile(dest, overwrite: true);
                }
            }

            File.WriteAllText(stampFile, hash);
            _bundleAvailable = true;
            return true;
        }
        catch
        {
            _bundleAvailable = false;
            return false;
        }
    }

    private static string NormalizeRelative(string relativePath)
    {
        var parts = relativePath.Split('/', '\\')
            .Where(p => p.Length > 0 && p != ".")
            .ToList();
        if (parts.Contains("..")) throw new ArgumentException("Invalid relative path: " + relativePath);
        return string.Join(Path.DirectorySeparatorChar.ToString(), parts);
    }

    private static string ComputeSha256(Stream stream)
    {
        using var sha = SHA256.Create();
        var data = sha.ComputeHash(stream);
        return BitConverter.ToString(data).Replace("-", "").ToLowerInvariant();
    }
}
