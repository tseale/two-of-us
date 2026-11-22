// GENERATED FILE — do not edit by hand.
//
// Numbers exported from the sky lab's own modules, so the Swift is tested against what the
// signed-off mockup really computes:
//     design/sky-lab/skies/hill-painted.js   lookOf, read from the running page (window.__hillPainted.look)
//     design/sky-lab/lab/presence.js         MOMENT.rise
// To regenerate, from the repository's root:
//     node design/sky-lab/tools/swift-fixtures/look.mjs
// (`--check` only compares.) It rewrites this whole file; a hand edit here is lost, and is a lie
// about the lab.

import Foundation

/// The lab's numbers as comma-separated tables, one row a line: data only. They are read with
/// `SkyCoreFixture.rows` and `SkyCoreFixture.number` (TwoOfUsTests/SkyCoreFixture.swift).
enum SkyCoreFixturesLook {
    /// How far the camera has looked up, 0 on the hill … 1 up, `age` seconds into each event as the lab's own
    /// page plays it (skies/hill-painted.js, `lookOf`): a night sleep arriving from elsewhere, first light,
    /// and the bedtime moment's rise on the Duo (the cover) and on the slab; then the two quiet events under
    /// Reduce Motion, where `look` is the weight of the looked-up still in a dissolve.
    ///
    /// Columns: play, age, look.
    static let look = """
arrive,0,0
arrive,0.1,0.0006022144
arrive,0.2,0.004525260800000001
arrive,0.3,0.0143188992
arrive,0.4,0.031758745600000006
arrive,0.5,0.05792000000000001
arrive,0.6,0.0932511744
arrive,0.7,0.13764782079999996
arrive,0.8,0.19052625920000002
arrive,0.9,0.2508973056
arrive,1,0.31744000000000006
arrive,1.1,0.38857533440000014
arrive,1.2,0.4625399807999999
arrive,1.3,0.5374600192000001
arrive,1.4,0.6114246655999999
arrive,1.5,0.6825600000000001
arrive,1.6,0.7491026944
arrive,1.7,0.8094737408
arrive,1.8,0.8623521792000001
arrive,1.9,0.9067488256
arrive,2,0.9420800000000001
arrive,2.1,0.9682412543999999
arrive,2.2,0.9856811008000008
arrive,2.3,0.9954747391999994
arrive,2.4,0.9993977855999999
arrive,2.5,1
arrive,2.6,1
arrive,2.7,1
arrive,2.8,1
settle,0,1
settle,0.1,1
settle,0.2,0.9994633618193718
settle,0.3,0.995957370594113
settle,0.4,0.987174212818448
settle,0.5,0.9714726644455995
settle,0.6,0.9478174918460622
settle,0.7,0.915718852765875
settle,0.8,0.8751716972848935
settle,0.9,0.8265951687750644
settle,1,0.7707720048586966
settle,1.1,0.7087879383667347
settle,1.2,0.6419710982970324
settle,1.3,0.5718314107726243
settle,1.4,0.5000000000000001
settle,1.5,0.4281685892273758
settle,1.6,0.35802890170296786
settle,1.7,0.2912120616332655
settle,1.8,0.22922799514130332
settle,1.9,0.17340483122493555
settle,2,0.1248283027151067
settle,2.1,0.08428114723412505
settle,2.2,0.052182508153937546
settle,2.3,0.028527335554400457
settle,2.4,0.012825787181552362
settle,2.5,0.004042629405886622
settle,2.6,0.0005366381806285458
settle,2.7,0
settle,2.8,0
settle,2.9,0
settle,3,0
bedtime-duo,0,0
bedtime-duo,0.1,0
bedtime-duo,0.2,0
bedtime-duo,0.3,0
bedtime-duo,0.4,0.0010041377527147352
bedtime-duo,0.5,0.007451333843115044
bedtime-duo,0.6,0.023264116142083652
bedtime-duo,0.7,0.05086651872713235
bedtime-duo,0.8,0.09136037526985742
bedtime-duo,0.9,0.14470161242339508
bedtime-duo,1,0.20987654320987653
bedtime-duo,1.1,0.2850781604078841
bedtime-duo,1.2,0.3678824299399058
bedtime-duo,1.3,0.4554245842597918
bedtime-duo,1.4,0.544575415740208
bedtime-duo,1.5,0.6321175700600941
bedtime-duo,1.6,0.714921839592116
bedtime-duo,1.7,0.7901234567901235
bedtime-duo,1.8,0.8552983875766048
bedtime-duo,1.9,0.9086396247301424
bedtime-duo,2,0.9491334812728682
bedtime-duo,2.1,0.9767358838579168
bedtime-duo,2.2,0.9925486661568856
bedtime-duo,2.3,0.9989958622472848
bedtime-duo,2.4,1
bedtime-duo,2.5,1
bedtime-duo,2.6,1
bedtime-duo,2.7,1
bedtime-slab,0,0
bedtime-slab,0.1,0
bedtime-slab,0.2,0
bedtime-slab,0.3,0
bedtime-slab,0.4,0.0006789219232253088
bedtime-slab,0.5,0.005087770061728394
bedtime-slab,0.6,0.01605224609374999
bedtime-slab,0.7,0.035493827160493804
bedtime-slab,0.8,0.06452018831983022
bedtime-slab,0.9,0.103515625
bedtime-slab,1,0.15223147545331786
bedtime-slab,1.1,0.20987654320987653
bedtime-slab,1.2,0.27520751953124983
bedtime-slab,1.3,0.3466194058641974
bedtime-slab,1.4,0.42223593629436706
bedtime-slab,1.5,0.4999999999999999
bedtime-slab,1.6,0.5777640637056326
bedtime-slab,1.7,0.6533805941358024
bedtime-slab,1.8,0.7247924804687499
bedtime-slab,1.9,0.7901234567901233
bedtime-slab,2,0.8477685245466824
bedtime-slab,2.1,0.896484375
bedtime-slab,2.2,0.9354798116801702
bedtime-slab,2.3,0.9645061728395061
bedtime-slab,2.4,0.9839477539062507
bedtime-slab,2.5,0.9949122299382724
bedtime-slab,2.6,0.9993210780767756
bedtime-slab,2.7,1
bedtime-slab,2.8,1
bedtime-slab,2.9,1
bedtime-slab,3,1
arrive-reduced,0,0
arrive-reduced,0.05,0.01967592592592593
arrive-reduced,0.1,0.07407407407407408
arrive-reduced,0.15,0.15625
arrive-reduced,0.2,0.2592592592592593
arrive-reduced,0.25,0.37615740740740744
arrive-reduced,0.3,0.5
arrive-reduced,0.35,0.6238425925925927
arrive-reduced,0.4,0.7407407407407408
arrive-reduced,0.45,0.84375
arrive-reduced,0.5,0.925925925925926
arrive-reduced,0.55,0.9803240740740741
arrive-reduced,0.6,1
arrive-reduced,0.65,1
arrive-reduced,0.7,1
arrive-reduced,0.75,1
arrive-reduced,0.8,1
settle-reduced,0,1
settle-reduced,0.05,0.9803240740740741
settle-reduced,0.1,0.9259259259259259
settle-reduced,0.15,0.84375
settle-reduced,0.2,0.7407407407407407
settle-reduced,0.25,0.6238425925925926
settle-reduced,0.3,0.5
settle-reduced,0.35,0.37615740740740733
settle-reduced,0.4,0.2592592592592592
settle-reduced,0.45,0.15625
settle-reduced,0.5,0.07407407407407396
settle-reduced,0.55,0.01967592592592593
settle-reduced,0.6,0
settle-reduced,0.65,0
settle-reduced,0.7,0
settle-reduced,0.75,0
settle-reduced,0.8,0
"""

    /// When the bedtime moment's rise starts and ends on each display, in seconds since the tap
    /// (lab/presence.js, `MOMENT.rise`).
    ///
    /// Columns: display, starts, ends.
    static let rise = """
duo,0.3,2.4
slab,0.3,2.7
"""
}
