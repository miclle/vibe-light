"""Generate the parametric LED development-board battery round case.

Run from FreeCAD's Python console:

    script_path = "/path/to/generate_led_battery_round_case.py"
    scope = {"__name__": "__main__", "__file__": script_path}
    exec(compile(open(script_path, "rb").read(), script_path, "exec"), scope)

The generated FCStd keeps the source dimensions editable on the
``Parameters`` object. STEP and STL exports are emitted beside it.
"""

from pathlib import Path

import FreeCAD as App
import Mesh
import Part


DOCUMENT_NAME = "LEDBatteryRoundCase"
OUTPUT_STEM = "LED开发板锂电池圆盒"
OUTPUT_DIRECTORY = Path(__file__).resolve().parent


def add_length(parameters, name, label, value, description):
    parameters.addProperty("App::PropertyLength", name, "Dimensions", description)
    setattr(parameters, name, value)
    parameters.addProperty("App::PropertyString", f"{name}Label", "Parameter notes")
    setattr(parameters, f"{name}Label", label)
    parameters.setEditorMode(f"{name}Label", 1)


def build_model():
    if DOCUMENT_NAME in App.listDocuments():
        raise RuntimeError(
            f"FreeCAD document {DOCUMENT_NAME!r} is already open; "
            "close it before regenerating the model."
        )

    document = App.newDocument(DOCUMENT_NAME)
    document.Label = OUTPUT_STEM

    parameters = document.addObject("App::FeaturePython", "Parameters")
    parameters.Label = "设计参数（双击属性可修改）"
    add_length(parameters, "InternalDiameter", "内部直径", 100.0, "盒体内部净直径")
    add_length(parameters, "WallThickness", "侧壁厚度", 2.0, "圆柱侧壁厚度")
    add_length(parameters, "InternalHeight", "内部高度", 34.0, "底部开口到顶面内侧的净高度")
    add_length(parameters, "TopThickness", "封闭顶面厚度", 2.0, "封闭顶面的厚度")
    add_length(parameters, "CenterHoleX", "中心孔 X", 3.0, "顶面中心方孔 X 方向尺寸")
    add_length(parameters, "CenterHoleY", "中心孔 Y", 3.0, "顶面中心方孔 Y 方向尺寸")
    add_length(parameters, "SupportBaseDiameter", "固定座根部直径", 15.0, "弧面固定座贴合顶板外侧处的直径")
    add_length(parameters, "SupportTipDiameter", "固定座端部直径", 5.0, "弧面固定座朝向盒外端部的直径")
    add_length(parameters, "SupportHeight", "固定座高度", 10.0, "固定座从顶板外侧向盒外延伸的高度")
    add_length(parameters, "TypeCPortWidth", "Type-C 插口宽度", 10.8, "侧壁 Type-C 母座开孔的水平宽度")
    add_length(parameters, "TypeCPortHeight", "Type-C 插口高度", 5.4, "侧壁 Type-C 母座开孔的垂直高度")
    add_length(parameters, "TypeCPortSupportDepth", "Type-C 内部固定座高度", 5.0, "固定座从侧壁内表面向盒内延伸的径向深度")
    add_length(parameters, "BottomLidThickness", "底盖厚度", 3.0, "独立底盖的板厚")
    add_length(parameters, "LidFitClearance", "底盖配合总间隙", 0.4, "底盖直径相对盒体内径缩小的总量")
    add_length(parameters, "LidScrewHoleDiameter", "底盖螺丝通孔直径", 2.8, "适配 M2.5 螺丝的底盖通孔")
    add_length(parameters, "LidCountersinkDiameter", "底盖沉头孔大径", 5.2, "适配 M2.5 90°沉头螺丝的外侧大径")
    add_length(parameters, "ScrewBossDiameter", "螺丝柱外径", 7.0, "盒体内部四根螺丝柱的外径")
    add_length(parameters, "ScrewBossHeight", "螺丝柱高度", 8.0, "螺丝柱从底部开口向盒内延伸的高度")
    add_length(parameters, "ScrewPilotHoleDiameter", "螺丝柱底孔直径", 2.2, "适配 M2.5 自攻螺丝的柱内底孔")
    add_length(parameters, "ScrewCircleRadius", "螺丝孔分布圆半径", 46.8, "四颗螺丝的中心分布圆半径")
    add_length(parameters, "BatteryLength", "电池组长度", 70.0, "18650 电池组 X 方向包络")
    add_length(parameters, "BatteryWidth", "电池组宽度", 56.0, "18650 电池组 Y 方向包络")
    add_length(parameters, "BatteryHeight", "电池组高度", 19.0, "18650 电池组 Z 方向包络")
    add_length(parameters, "BatteryOffsetY", "电池组 Y 偏移", 6.085, "为侧壁竖装开发板让出的电池中心偏移")
    add_length(parameters, "BatteryFitClearance", "电池定位总间隙", 0.4, "电池定位边在长宽方向预留的总间隙")
    add_length(parameters, "BatteryRailThickness", "电池定位边厚度", 1.5, "底盖内侧电池定位边厚度")
    add_length(parameters, "BatteryRailHeight", "电池定位边高度", 3.0, "定位边高出底盖内表面的高度")
    add_length(parameters, "BatterySideRailLength", "电池侧定位边长度", 40.0, "前后两段定位边的长度")
    add_length(parameters, "BatteryEndRailLength", "电池端定位边长度", 20.0, "左右两段定位边的长度")
    add_length(parameters, "DevelopmentBoardLength", "开发板长度", 64.0, "带针脚开发板 X 方向包络")
    add_length(parameters, "DevelopmentBoardWidth", "开发板宽度", 28.4, "带针脚开发板 Y 方向包络")
    add_length(parameters, "DevelopmentBoardHeight", "开发板高度", 13.0, "带针脚开发板 Z 方向包络")
    add_length(parameters, "BatteryBoardGap", "电池与开发板间距", 2.0, "电池与侧装开发板之间的 Y 方向净距")
    add_length(parameters, "BoardFitClearance", "开发板卡槽总间隙", 0.4, "开发板卡槽在长宽方向预留的总间隙")
    add_length(parameters, "BoardRailThickness", "开发板卡槽壁厚", 1.5, "开发板侧装导轨与端挡的厚度")
    add_length(parameters, "BoardRailHeight", "开发板卡槽高度", 8.0, "开发板侧装卡槽高出底盖内表面的高度")
    add_length(parameters, "BoardSideRailLength", "开发板侧导轨长度", 40.0, "开发板前后侧导轨的长度")
    add_length(parameters, "BoardEndRailWidth", "开发板端挡宽度", 6.0, "开发板左右端挡沿 Y 方向的宽度")
    add_length(
        parameters,
        "CutAllowance",
        "布尔运算余量",
        0.1,
        "仅用于确保切除体完全贯穿，不改变成品尺寸",
    )

    parameters.addProperty(
        "App::PropertyLength",
        "OuterDiameter",
        "Calculated",
        "外径 = 内径 + 2 × 侧壁厚度",
    )
    parameters.setExpression(
        "OuterDiameter",
        "InternalDiameter + 2 * WallThickness",
    )
    parameters.setEditorMode("OuterDiameter", 1)

    parameters.addProperty(
        "App::PropertyLength",
        "TotalHeight",
        "Calculated",
        "总高 = 内部高度 + 封闭面厚度",
    )
    parameters.setExpression(
        "TotalHeight",
        "InternalHeight + TopThickness",
    )
    parameters.setEditorMode("TotalHeight", 1)

    parameters.addProperty(
        "App::PropertyLength",
        "SupportMidDiameter",
        "Calculated",
        "弧面中段直径，用于形成向中心收束的内凹轮廓",
    )
    parameters.setExpression(
        "SupportMidDiameter",
        "(SupportBaseDiameter + 3 * SupportTipDiameter) / 4",
    )
    parameters.setEditorMode("SupportMidDiameter", 1)

    parameters.addProperty(
        "App::PropertyLength",
        "TypeCPortCenterHeight",
        "Calculated",
        "Type-C 插口中心距盒体底部的高度",
    )
    parameters.setExpression(
        "TypeCPortCenterHeight",
        "InternalHeight / 2",
    )
    parameters.setEditorMode("TypeCPortCenterHeight", 1)

    parameters.addProperty(
        "App::PropertyLength",
        "LidCountersinkDepth",
        "Calculated",
        "90°沉头孔深度 =（沉头大径 - 通孔直径）/ 2",
    )
    parameters.setExpression(
        "LidCountersinkDepth",
        "(LidCountersinkDiameter - LidScrewHoleDiameter) / 2",
    )
    parameters.setEditorMode("LidCountersinkDepth", 1)

    parameters.addProperty(
        "App::PropertyLength",
        "BoardTopClearance",
        "Calculated",
        "开发板包络顶面到盒体顶面内侧的净距",
    )
    parameters.setExpression(
        "BoardTopClearance",
        "InternalHeight - BottomLidThickness - DevelopmentBoardWidth",
    )
    parameters.setEditorMode("BoardTopClearance", 1)

    parameters.addProperty(
        "App::PropertyString",
        "ModelDescription",
        "Documentation",
        "模型说明",
    )
    parameters.ModelDescription = (
        "顶面封闭、底部开口的圆形盒体；顶面中心 3 × 3 mm 方孔贯穿封闭面与"
        "顶面外侧平滑内凹弧面固定座。固定座根部直径 15 mm、端部直径 5 mm、"
        "高 10 mm，侧面采用向中心收束的内凹弧线过渡；正前方侧壁设有"
        "10.8 × 5.4 mm Type-C 母座插口，内侧设有径向深度 5 mm、"
        "开孔四周厚 2 mm 的加强固定座。底部设有直径等于内部直径的"
        "独立 3 mm 厚内嵌底盖，直径比内腔小 0.4 mm；外侧设四个 M2.5 90°沉头孔，通过螺丝"
        "连接到盒体内部从底盖内表面开始、高 8 mm 的螺丝柱。盒体内径扩大为"
        "100 mm、内部高 34 mm：70 × 56 × 19 mm 电池组平放并向后偏置，"
        "64 × 28.4 × 13 mm 带针脚开发板在 Type-C 一侧竖装，13 mm 厚度"
        "沿径向、28.4 mm 沿高度，与电池侧向间距 2 mm。底盖内侧"
        "设四段电池定位边及 8 mm 高开发板侧装卡槽；四根螺丝柱采用半径 46.8 mm 的十字分布，前柱位于"
        "Type-C 插口下方。"
    )
    parameters.setEditorMode("ModelDescription", 1)

    outer = document.addObject("Part::Cylinder", "OuterCylinder")
    outer.Label = "外圆柱（构造体）"
    outer.setExpression("Radius", "Parameters.OuterDiameter / 2")
    outer.setExpression("Height", "Parameters.TotalHeight")

    cavity = document.addObject("Part::Cylinder", "InnerCavity")
    cavity.Label = "内部空腔（切除体）"
    cavity.setExpression("Radius", "Parameters.InternalDiameter / 2")
    cavity.setExpression("Height", "Parameters.InternalHeight + Parameters.CutAllowance")
    cavity.setExpression("Placement.Base.z", "-Parameters.CutAllowance")

    shell = document.addObject("Part::Cut", "OpenBottomShell")
    shell.Label = "底部开口盒体"
    shell.Base = outer
    shell.Tool = cavity
    shell.Refine = True

    support_base_profile = document.addObject("Part::Circle", "SupportBaseProfile")
    support_base_profile.Label = "固定座根部截面（构造线）"
    support_base_profile.setExpression("Radius", "Parameters.SupportBaseDiameter / 2")
    support_base_profile.setExpression(
        "Placement.Base.z",
        "Parameters.TotalHeight",
    )

    support_mid_profile = document.addObject("Part::Circle", "SupportMidProfile")
    support_mid_profile.Label = "固定座弧面中段截面（构造线）"
    support_mid_profile.setExpression("Radius", "Parameters.SupportMidDiameter / 2")
    support_mid_profile.setExpression(
        "Placement.Base.z",
        "Parameters.TotalHeight + Parameters.SupportHeight / 2",
    )

    support_tip_profile = document.addObject("Part::Circle", "SupportTipProfile")
    support_tip_profile.Label = "固定座端部截面（构造线）"
    support_tip_profile.setExpression("Radius", "Parameters.SupportTipDiameter / 2")
    support_tip_profile.setExpression(
        "Placement.Base.z",
        "Parameters.TotalHeight + Parameters.SupportHeight",
    )

    support_outer = document.addObject("Part::Loft", "CurvedSupportOuter")
    support_outer.Label = "顶面外置平滑内凹弧面固定座外形"
    support_outer.Sections = [
        support_base_profile,
        support_mid_profile,
        support_tip_profile,
    ]
    support_outer.Solid = True
    support_outer.Ruled = False
    support_outer.Closed = False

    supported_shell = document.addObject("Part::Fuse", "ShellWithSupport")
    supported_shell.Label = "盒体与外置固定座融合体"
    supported_shell.Base = shell
    supported_shell.Tool = support_outer
    supported_shell.Refine = True

    center_hole = document.addObject("Part::Box", "CenterSquareHole")
    center_hole.Label = "中心方孔（切除体）"
    center_hole.setExpression("Length", "Parameters.CenterHoleX")
    center_hole.setExpression("Width", "Parameters.CenterHoleY")
    center_hole.setExpression(
        "Height",
        "Parameters.SupportHeight + Parameters.TopThickness + 2 * Parameters.CutAllowance",
    )
    center_hole.setExpression("Placement.Base.x", "-Parameters.CenterHoleX / 2")
    center_hole.setExpression("Placement.Base.y", "-Parameters.CenterHoleY / 2")
    center_hole.setExpression(
        "Placement.Base.z",
        "Parameters.InternalHeight - Parameters.CutAllowance",
    )

    case_with_center_hole = document.addObject("Part::Cut", "CaseWithCenterHole")
    case_with_center_hole.Label = "盒体与顶面贯穿孔"
    case_with_center_hole.Base = supported_shell
    case_with_center_hole.Tool = center_hole
    case_with_center_hole.Refine = True

    type_c_support = document.addObject("Part::Box", "TypeCPortSupportOuter")
    type_c_support.Label = "Type-C 内部加强固定座外形"
    type_c_support.setExpression(
        "Length",
        "Parameters.TypeCPortWidth + 2 * Parameters.WallThickness",
    )
    type_c_support.setExpression(
        "Width",
        "Parameters.TypeCPortSupportDepth + Parameters.CutAllowance",
    )
    type_c_support.setExpression(
        "Height",
        "Parameters.TypeCPortHeight + 2 * Parameters.WallThickness",
    )
    type_c_support.setExpression(
        "Placement.Base.x",
        "-Parameters.TypeCPortWidth / 2 - Parameters.WallThickness",
    )
    type_c_support.setExpression(
        "Placement.Base.y",
        "-Parameters.InternalDiameter / 2 - Parameters.CutAllowance",
    )
    type_c_support.setExpression(
        "Placement.Base.z",
        "Parameters.TypeCPortCenterHeight - Parameters.TypeCPortHeight / 2 "
        "- Parameters.WallThickness",
    )

    case_with_type_c_support = document.addObject("Part::Fuse", "CaseWithTypeCSupport")
    case_with_type_c_support.Label = "盒体与 Type-C 内部固定座融合体"
    case_with_type_c_support.Base = case_with_center_hole
    case_with_type_c_support.Tool = type_c_support
    case_with_type_c_support.Refine = True

    type_c_port = document.addObject("Part::Box", "TypeCPortCutout")
    type_c_port.Label = "Type-C 母座插口（切除体）"
    type_c_port.setExpression("Length", "Parameters.TypeCPortWidth")
    type_c_port.setExpression(
        "Width",
        "Parameters.WallThickness + Parameters.TypeCPortSupportDepth "
        "+ 2 * Parameters.CutAllowance",
    )
    type_c_port.setExpression("Height", "Parameters.TypeCPortHeight")
    type_c_port.setExpression("Placement.Base.x", "-Parameters.TypeCPortWidth / 2")
    type_c_port.setExpression(
        "Placement.Base.y",
        "-Parameters.OuterDiameter / 2 - Parameters.CutAllowance",
    )
    type_c_port.setExpression(
        "Placement.Base.z",
        "Parameters.TypeCPortCenterHeight - Parameters.TypeCPortHeight / 2",
    )

    case_without_bosses = document.addObject("Part::Cut", "CaseWithoutScrewBosses")
    case_without_bosses.Label = "带 Type-C 插口的盒体"
    case_without_bosses.Base = case_with_type_c_support
    case_without_bosses.Tool = type_c_port
    case_without_bosses.Refine = True

    screw_bosses = []
    screw_pilot_holes = []
    lid_screw_holes = []
    lid_countersinks = []
    screw_positions = (
        ("Front", "0 mm", "-Parameters.ScrewCircleRadius"),
        ("Right", "Parameters.ScrewCircleRadius", "0 mm"),
        ("Rear", "0 mm", "Parameters.ScrewCircleRadius"),
        ("Left", "-Parameters.ScrewCircleRadius", "0 mm"),
    )
    for position_name, x_expression, y_expression in screw_positions:

            boss = document.addObject("Part::Cylinder", f"ScrewBoss{position_name}")
            boss.Label = f"螺丝柱外形（{position_name}）"
            boss.setExpression("Radius", "Parameters.ScrewBossDiameter / 2")
            boss.setExpression("Height", "Parameters.ScrewBossHeight")
            boss.setExpression(
                "Placement.Base.x",
                x_expression,
            )
            boss.setExpression(
                "Placement.Base.y",
                y_expression,
            )
            boss.setExpression(
                "Placement.Base.z",
                "Parameters.BottomLidThickness",
            )
            screw_bosses.append(boss)

            pilot_hole = document.addObject(
                "Part::Cylinder",
                f"ScrewPilotHole{position_name}",
            )
            pilot_hole.Label = f"螺丝柱底孔（{position_name}）"
            pilot_hole.setExpression(
                "Radius",
                "Parameters.ScrewPilotHoleDiameter / 2",
            )
            pilot_hole.setExpression(
                "Height",
                "Parameters.ScrewBossHeight + 2 * Parameters.CutAllowance",
            )
            pilot_hole.setExpression(
                "Placement.Base.x",
                x_expression,
            )
            pilot_hole.setExpression(
                "Placement.Base.y",
                y_expression,
            )
            pilot_hole.setExpression(
                "Placement.Base.z",
                "Parameters.BottomLidThickness - Parameters.CutAllowance",
            )
            screw_pilot_holes.append(pilot_hole)

            lid_hole = document.addObject(
                "Part::Cylinder",
                f"LidScrewHole{position_name}",
            )
            lid_hole.Label = f"底盖螺丝通孔（{position_name}）"
            lid_hole.setExpression(
                "Radius",
                "Parameters.LidScrewHoleDiameter / 2",
            )
            lid_hole.setExpression(
                "Height",
                "Parameters.BottomLidThickness + 2 * Parameters.CutAllowance",
            )
            lid_hole.setExpression(
                "Placement.Base.x",
                x_expression,
            )
            lid_hole.setExpression(
                "Placement.Base.y",
                y_expression,
            )
            lid_hole.setExpression(
                "Placement.Base.z",
                "-Parameters.CutAllowance",
            )
            lid_screw_holes.append(lid_hole)

            countersink = document.addObject(
                "Part::Cone",
                f"LidCountersink{position_name}",
            )
            countersink.Label = f"底盖 90°沉头孔（{position_name}）"
            countersink.setExpression(
                "Radius1",
                "Parameters.LidCountersinkDiameter / 2 + Parameters.CutAllowance",
            )
            countersink.setExpression(
                "Radius2",
                "Parameters.LidScrewHoleDiameter / 2",
            )
            countersink.setExpression(
                "Height",
                "Parameters.LidCountersinkDepth + Parameters.CutAllowance",
            )
            countersink.setExpression(
                "Placement.Base.x",
                x_expression,
            )
            countersink.setExpression(
                "Placement.Base.y",
                y_expression,
            )
            countersink.setExpression(
                "Placement.Base.z",
                "-Parameters.CutAllowance",
            )
            lid_countersinks.append(countersink)

    screw_boss_outer_union = document.addObject("Part::MultiFuse", "ScrewBossOuterUnion")
    screw_boss_outer_union.Label = "四根螺丝柱外形融合体"
    screw_boss_outer_union.Shapes = screw_bosses
    screw_boss_outer_union.Refine = True

    case_with_screw_bosses = document.addObject("Part::Fuse", "CaseWithScrewBosses")
    case_with_screw_bosses.Label = "盒体与四根螺丝柱融合体"
    case_with_screw_bosses.Base = case_without_bosses
    case_with_screw_bosses.Tool = screw_boss_outer_union
    case_with_screw_bosses.Refine = True

    screw_pilot_hole_union = document.addObject("Part::MultiFuse", "ScrewPilotHoleUnion")
    screw_pilot_hole_union.Label = "四个螺丝柱底孔切除体"
    screw_pilot_hole_union.Shapes = screw_pilot_holes
    screw_pilot_hole_union.Refine = True

    case = document.addObject("Part::Cut", "RoundCase")
    case.Label = "LED 开发板锂电池圆盒"
    case.Base = case_with_screw_bosses
    case.Tool = screw_pilot_hole_union
    case.Refine = True

    bottom_lid_blank = document.addObject("Part::Cylinder", "BottomLidBlank")
    bottom_lid_blank.Label = "底盖圆板（构造体）"
    bottom_lid_blank.setExpression(
        "Radius",
        "(Parameters.InternalDiameter - Parameters.LidFitClearance) / 2",
    )
    bottom_lid_blank.setExpression("Height", "Parameters.BottomLidThickness")

    battery_rails = []
    rail_specs = (
        (
            "Front",
            "Parameters.BatterySideRailLength",
            "Parameters.BatteryRailThickness",
            "-Parameters.BatterySideRailLength / 2",
            "-(Parameters.BatteryWidth + Parameters.BatteryFitClearance) / 2 "
            "- Parameters.BatteryRailThickness + Parameters.BatteryOffsetY",
        ),
        (
            "Rear",
            "Parameters.BatterySideRailLength",
            "Parameters.BatteryRailThickness",
            "-Parameters.BatterySideRailLength / 2",
            "(Parameters.BatteryWidth + Parameters.BatteryFitClearance) / 2 "
            "+ Parameters.BatteryOffsetY",
        ),
        (
            "Left",
            "Parameters.BatteryRailThickness",
            "Parameters.BatteryEndRailLength",
            "-(Parameters.BatteryLength + Parameters.BatteryFitClearance) / 2 "
            "- Parameters.BatteryRailThickness",
            "-Parameters.BatteryEndRailLength / 2 + Parameters.BatteryOffsetY",
        ),
        (
            "Right",
            "Parameters.BatteryRailThickness",
            "Parameters.BatteryEndRailLength",
            "(Parameters.BatteryLength + Parameters.BatteryFitClearance) / 2",
            "-Parameters.BatteryEndRailLength / 2 + Parameters.BatteryOffsetY",
        ),
    )
    for position_name, length, width, x_position, y_position in rail_specs:
        rail = document.addObject("Part::Box", f"BatteryRail{position_name}")
        rail.Label = f"底盖电池定位边（{position_name}）"
        rail.setExpression("Length", length)
        rail.setExpression("Width", width)
        rail.setExpression(
            "Height",
            "Parameters.BatteryRailHeight + Parameters.CutAllowance",
        )
        rail.setExpression("Placement.Base.x", x_position)
        rail.setExpression("Placement.Base.y", y_position)
        rail.setExpression(
            "Placement.Base.z",
            "Parameters.BottomLidThickness - Parameters.CutAllowance",
        )
        battery_rails.append(rail)

    board_rails = []
    board_rail_specs = (
        (
            "Front",
            "Parameters.BoardSideRailLength",
            "Parameters.BoardRailThickness",
            "-Parameters.BoardSideRailLength / 2",
            "Parameters.BatteryOffsetY - Parameters.BatteryWidth / 2 "
            "- Parameters.BatteryBoardGap - Parameters.DevelopmentBoardHeight "
            "- Parameters.BoardFitClearance / 2 - Parameters.BoardRailThickness",
        ),
        (
            "Rear",
            "Parameters.BoardSideRailLength",
            "Parameters.BoardRailThickness",
            "-Parameters.BoardSideRailLength / 2",
            "Parameters.BatteryOffsetY - Parameters.BatteryWidth / 2 "
            "- Parameters.BatteryBoardGap + Parameters.BoardFitClearance / 2",
        ),
        (
            "Left",
            "Parameters.BoardRailThickness",
            "Parameters.BoardEndRailWidth",
            "-Parameters.DevelopmentBoardLength / 2 "
            "- Parameters.BoardFitClearance / 2 - Parameters.BoardRailThickness",
            "Parameters.BatteryOffsetY - Parameters.BatteryWidth / 2 "
            "- Parameters.BatteryBoardGap - Parameters.DevelopmentBoardHeight / 2 "
            "- Parameters.BoardEndRailWidth / 2",
        ),
        (
            "Right",
            "Parameters.BoardRailThickness",
            "Parameters.BoardEndRailWidth",
            "Parameters.DevelopmentBoardLength / 2 + Parameters.BoardFitClearance / 2",
            "Parameters.BatteryOffsetY - Parameters.BatteryWidth / 2 "
            "- Parameters.BatteryBoardGap - Parameters.DevelopmentBoardHeight / 2 "
            "- Parameters.BoardEndRailWidth / 2",
        ),
    )
    for position_name, length, width, x_position, y_position in board_rail_specs:
        rail = document.addObject("Part::Box", f"BoardRail{position_name}")
        rail.Label = f"开发板侧装卡槽（{position_name}）"
        rail.setExpression("Length", length)
        rail.setExpression("Width", width)
        rail.setExpression(
            "Height",
            "Parameters.BoardRailHeight + Parameters.CutAllowance",
        )
        rail.setExpression("Placement.Base.x", x_position)
        rail.setExpression("Placement.Base.y", y_position)
        rail.setExpression(
            "Placement.Base.z",
            "Parameters.BottomLidThickness - Parameters.CutAllowance",
        )
        board_rails.append(rail)

    bottom_lid_with_rails = document.addObject(
        "Part::MultiFuse",
        "BottomLidWithBatteryRails",
    )
    bottom_lid_with_rails.Label = "底盖与电池、开发板定位结构融合体"
    bottom_lid_with_rails.Shapes = [bottom_lid_blank] + battery_rails + board_rails
    bottom_lid_with_rails.Refine = True

    lid_screw_hole_union = document.addObject("Part::MultiFuse", "LidScrewHoleUnion")
    lid_screw_hole_union.Label = "底盖四组通孔与 90°沉头孔切除体"
    lid_screw_hole_union.Shapes = lid_screw_holes + lid_countersinks
    lid_screw_hole_union.Refine = True

    bottom_lid = document.addObject("Part::Cut", "BottomLid")
    bottom_lid.Label = "带四颗 M2.5 90°沉头孔的底盖"
    bottom_lid.Base = bottom_lid_with_rails
    bottom_lid.Tool = lid_screw_hole_union
    bottom_lid.Refine = True

    battery_envelope = document.addObject("Part::Box", "BatteryEnvelope")
    battery_envelope.Label = "18650 电池组安装包络（参考）"
    battery_envelope.setExpression("Length", "Parameters.BatteryLength")
    battery_envelope.setExpression("Width", "Parameters.BatteryWidth")
    battery_envelope.setExpression("Height", "Parameters.BatteryHeight")
    battery_envelope.setExpression("Placement.Base.x", "-Parameters.BatteryLength / 2")
    battery_envelope.setExpression(
        "Placement.Base.y",
        "-Parameters.BatteryWidth / 2 + Parameters.BatteryOffsetY",
    )
    battery_envelope.setExpression("Placement.Base.z", "Parameters.BottomLidThickness")

    board_envelope = document.addObject("Part::Box", "DevelopmentBoardEnvelope")
    board_envelope.Label = "带针脚开发板安装包络（参考）"
    board_envelope.setExpression("Length", "Parameters.DevelopmentBoardLength")
    board_envelope.setExpression("Width", "Parameters.DevelopmentBoardHeight")
    board_envelope.setExpression("Height", "Parameters.DevelopmentBoardWidth")
    board_envelope.setExpression("Placement.Base.x", "-Parameters.DevelopmentBoardLength / 2")
    board_envelope.setExpression(
        "Placement.Base.y",
        "Parameters.BatteryOffsetY - Parameters.BatteryWidth / 2 "
        "- Parameters.BatteryBoardGap - Parameters.DevelopmentBoardHeight",
    )
    board_envelope.setExpression(
        "Placement.Base.z",
        "Parameters.BottomLidThickness",
    )

    document.recompute()

    case.addProperty("App::PropertyString", "PrintOrientation", "Documentation")
    case.PrintOrientation = "底部开口朝下、封闭顶面朝上"
    case.setEditorMode("PrintOrientation", 1)
    case.addProperty("App::PropertyString", "NominalDimensions", "Documentation")
    case.NominalDimensions = (
        "内径 100 mm；壁厚 2 mm；内部高度 34 mm；顶面方孔 3 × 3 mm；"
        "顶面外侧平滑内凹弧面固定座直径 15 → 5 mm，高 10 mm；"
        "正前方 Type-C 插口 10.8 × 5.4 mm，中心高 17 mm；"
        "内侧固定座径向深度 5 mm，开孔四周加强边 2 mm；"
        "内嵌底盖 Ø99.6 × 3 mm（单边配合间隙 0.2 mm）；四孔沿半径 46.8 mm 十字分布；M2.5 通孔 Ø2.8 mm；"
        "90°沉头孔大径 Ø5.2 mm、深 1.2 mm；"
        "螺丝柱 Ø7 × 8 mm，柱内底孔 Ø2.2 mm；电池组 70 × 56 × 19 mm，"
        "开发板包络 64 × 28.4 × 13 mm（保留针脚）通过底盖 8 mm 高卡槽在前侧竖装，"
        "与电池侧向间距 2 mm，开发板顶面距盒体顶面内侧 2.6 mm"
    )
    case.setEditorMode("NominalDimensions", 1)

    bottom_lid.addProperty("App::PropertyString", "PrintOrientation", "Documentation")
    bottom_lid.PrintOrientation = "圆形外侧平面朝下打印"
    bottom_lid.setEditorMode("PrintOrientation", 1)
    bottom_lid.addProperty("App::PropertyString", "NominalDimensions", "Documentation")
    bottom_lid.NominalDimensions = (
        "外径 99.6 mm（相对盒体内径单边间隙 0.2 mm）；厚 3 mm；四颗 M2.5 通孔 Ø2.8 mm；"
        "外侧 90°沉头孔 Ø5.2 mm、深 1.2 mm；孔位沿半径 46.8 mm 十字分布；"
        "内侧四段 1.5 × 3 mm 电池定位边，定位包络 70.4 × 56.4 mm，"
        "定位中心沿 Y 方向后移 6.085 mm；前侧设 0.4 mm 总间隙、8 mm 高的开发板卡槽"
    )
    bottom_lid.setEditorMode("NominalDimensions", 1)

    outer.ViewObject.Visibility = False
    cavity.ViewObject.Visibility = False
    shell.ViewObject.Visibility = False
    support_base_profile.ViewObject.Visibility = False
    support_mid_profile.ViewObject.Visibility = False
    support_tip_profile.ViewObject.Visibility = False
    support_outer.ViewObject.Visibility = False
    supported_shell.ViewObject.Visibility = False
    center_hole.ViewObject.Visibility = False
    case_with_center_hole.ViewObject.Visibility = False
    type_c_support.ViewObject.Visibility = False
    case_with_type_c_support.ViewObject.Visibility = False
    type_c_port.ViewObject.Visibility = False
    case_without_bosses.ViewObject.Visibility = False
    for construction_object in (
        screw_bosses + screw_pilot_holes + lid_screw_holes + lid_countersinks
    ):
        construction_object.ViewObject.Visibility = False
    screw_boss_outer_union.ViewObject.Visibility = False
    case_with_screw_bosses.ViewObject.Visibility = False
    screw_pilot_hole_union.ViewObject.Visibility = False
    bottom_lid_blank.ViewObject.Visibility = False
    for battery_rail in battery_rails:
        battery_rail.ViewObject.Visibility = False
    for board_rail in board_rails:
        board_rail.ViewObject.Visibility = False
    bottom_lid_with_rails.ViewObject.Visibility = False
    lid_screw_hole_union.ViewObject.Visibility = False
    battery_envelope.ViewObject.Visibility = False
    board_envelope.ViewObject.Visibility = False
    case.ViewObject.ShapeColor = (0.82, 0.84, 0.88)
    case.ViewObject.LineColor = (0.16, 0.18, 0.22)
    case.ViewObject.DisplayMode = "Flat Lines"
    bottom_lid.ViewObject.ShapeColor = (0.58, 0.62, 0.70)
    bottom_lid.ViewObject.LineColor = (0.12, 0.14, 0.18)
    bottom_lid.ViewObject.DisplayMode = "Flat Lines"

    fcstd_path = OUTPUT_DIRECTORY / f"{OUTPUT_STEM}.FCStd"
    step_path = OUTPUT_DIRECTORY / f"{OUTPUT_STEM}.step"
    stl_path = OUTPUT_DIRECTORY / f"{OUTPUT_STEM}.stl"
    lid_step_path = OUTPUT_DIRECTORY / f"{OUTPUT_STEM}_底盖.step"
    lid_stl_path = OUTPUT_DIRECTORY / f"{OUTPUT_STEM}_底盖.stl"

    document.recompute()
    document.saveAs(str(fcstd_path))
    Part.export([case], str(step_path))
    Mesh.export([case], str(stl_path))
    Part.export([bottom_lid], str(lid_step_path))
    Mesh.export([bottom_lid], str(lid_stl_path))

    print(f"Saved: {fcstd_path}")
    print(f"Saved: {step_path}")
    print(f"Saved: {stl_path}")
    print(f"Saved: {lid_step_path}")
    print(f"Saved: {lid_stl_path}")
    return document


if __name__ == "__main__":
    build_model()
