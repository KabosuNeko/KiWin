using System.Collections.Generic;
using KiWin.Core;
using Xunit;

namespace KiWin.Core.Tests;

public class Win11DebloatArgsTests
{
    [Theory]
    [InlineData("-Silent")]
    [InlineData("-RemoveApps")]
    [InlineData("-RemoveGamingApps")]
    [InlineData("-DisableTelemetry")]
    [InlineData("-DisableAISvcAutoStart")]
    public void Keeps_well_formed_flags(string flag)
    {
        var kept = StepCatalog.FilterWin11DebloatArgs(new[] { flag });
        Assert.Equal(new[] { flag }, kept);
    }

    [Theory]
    [InlineData("; Remove-Item -Recurse C:\\")]
    [InlineData("-Silent; calc.exe")]
    [InlineData("$(Get-Process)")]
    [InlineData("& whoami")]
    [InlineData("| Out-File pwned.txt")]
    [InlineData("-X `n Write-Host pwned")]
    [InlineData("'quoted'")]
    [InlineData("--double")]
    [InlineData("notaflag")]
    [InlineData("-bad flag")]
    public void Drops_anything_that_is_not_a_bare_flag(string bad)
    {
        var dropped = new List<string>();
        var kept = StepCatalog.FilterWin11DebloatArgs(new[] { bad }, dropped.Add);
        Assert.Empty(kept);
        Assert.Contains(bad, dropped);
    }

    [Fact]
    public void Keeps_injection_free_subset_and_reports_the_rest()
    {
        var input = new[] { "-Silent", "-Silent; rm", "-RemoveApps", "$(x)", "-DisableBing" };
        var dropped = new List<string>();
        var kept = StepCatalog.FilterWin11DebloatArgs(input, dropped.Add);
        Assert.Equal(new[] { "-Silent", "-RemoveApps", "-DisableBing" }, kept);
        Assert.Equal(new[] { "-Silent; rm", "$(x)" }, dropped);
    }

    [Fact]
    public void Ignores_empty_and_whitespace_entries()
    {
        var kept = StepCatalog.FilterWin11DebloatArgs(new[] { "", "   ", "\t" });
        Assert.Empty(kept);
    }

    [Fact]
    public void Defaults_are_all_valid()
    {
        var kept = StepCatalog.FilterWin11DebloatArgs(StepCatalog.DefaultWin11DebloatArgs);
        Assert.Equal(StepCatalog.DefaultWin11DebloatArgs.Length, kept.Count);
    }
}

public class InstallPlanTests
{
    [Theory]
    [InlineData("  -Silent   -RemoveApps ", "-Silent -RemoveApps")]
    [InlineData("", "")]
    [InlineData(null, "")]
    public void NormalizeWin11DebloatArgsText_collapses_whitespace(string? input, string expected)
    {
        Assert.Equal(expected, InstallPlan.NormalizeWin11DebloatArgsText(input!));
    }
}

public class StepCatalogTests
{
    [Theory]
    [InlineData("remove-edge-permanently", "Remove Edge Permanently")]
    [InlineData("wpbt", "Wpbt")]
    public void ToTitleLabel_titlecases_slug(string slug, string expected)
    {
        Assert.Equal(expected, StepCatalog.ToTitleLabel(slug));
    }
}
