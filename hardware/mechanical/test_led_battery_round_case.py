"""Regression tests for the parametric LED battery round case."""

import importlib.util
from pathlib import Path
import math
import tempfile
import unittest

import FreeCAD as App


GENERATOR_PATH = Path(__file__).with_name("generate_led_battery_round_case.py")


def load_generator():
    spec = importlib.util.spec_from_file_location(
        "generate_led_battery_round_case_under_test",
        GENERATOR_PATH,
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CurvedExternalSupportGeometryTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.generator = load_generator()
        self.generator.DOCUMENT_NAME = "LEDBatteryRoundCaseExternalSupportTest"
        self.generator.OUTPUT_DIRECTORY = Path(self.temporary_directory.name)

        if self.generator.DOCUMENT_NAME in App.listDocuments():
            App.closeDocument(self.generator.DOCUMENT_NAME)

        self.document = self.generator.build_model()
        self.document.recompute()

    def tearDown(self):
        if self.generator.DOCUMENT_NAME in App.listDocuments():
            App.closeDocument(self.generator.DOCUMENT_NAME)
        self.temporary_directory.cleanup()

    def test_support_uses_requested_external_dimensions(self):
        parameters = self.document.getObject("Parameters")
        case_shape = self.document.getObject("RoundCase").Shape

        self.assertAlmostEqual(parameters.SupportHeight.Value, 10.0)
        self.assertAlmostEqual(parameters.SupportBaseDiameter.Value, 15.0)
        self.assertAlmostEqual(parameters.SupportTipDiameter.Value, 5.0)

        is_inside = lambda x, y, z: case_shape.isInside(
            App.Vector(x, y, z),
            1e-7,
            True,
        )
        self.assertFalse(is_inside(3.5, 0, 33.9))
        self.assertTrue(is_inside(7.3, 0, 36.1))
        self.assertFalse(is_inside(7.6, 0, 36.1))
        self.assertTrue(is_inside(2.3, 0, 45.9))
        self.assertFalse(is_inside(3.0, 0, 45.9))
        self.assertFalse(is_inside(0, 0, 44.0))

    def test_support_side_profile_curves_inward(self):
        case_shape = self.document.getObject("RoundCase").Shape
        is_inside = lambda x, y, z: case_shape.isInside(
            App.Vector(x, y, z),
            1e-7,
            True,
        )

        self.assertTrue(is_inside(3.5, 0, 41.0))
        self.assertFalse(is_inside(4.0, 0, 41.0))

    def test_type_c_port_uses_requested_dimensions(self):
        parameters = self.document.getObject("Parameters")

        self.assertTrue(hasattr(parameters, "TypeCPortWidth"))
        self.assertTrue(hasattr(parameters, "TypeCPortHeight"))
        self.assertAlmostEqual(parameters.TypeCPortWidth.Value, 10.8)
        self.assertAlmostEqual(parameters.TypeCPortHeight.Value, 5.4)

    def test_type_c_port_opens_through_front_side_wall(self):
        case_shape = self.document.getObject("RoundCase").Shape
        is_inside = lambda x, y, z: case_shape.isInside(
            App.Vector(x, y, z),
            1e-7,
            True,
        )

        self.assertFalse(is_inside(0, -51.0, 17.0))
        self.assertFalse(is_inside(5.3, -51.0, 17.0))
        self.assertTrue(is_inside(5.6, -51.0, 17.0))
        self.assertFalse(is_inside(0, -51.0, 19.6))
        self.assertTrue(is_inside(0, -51.0, 19.8))

    def test_type_c_internal_support_uses_five_mm_depth(self):
        parameters = self.document.getObject("Parameters")

        self.assertTrue(hasattr(parameters, "TypeCPortSupportDepth"))
        self.assertAlmostEqual(parameters.TypeCPortSupportDepth.Value, 5.0)

    def test_type_c_internal_support_frame_surrounds_opening(self):
        case_shape = self.document.getObject("RoundCase").Shape
        is_inside = lambda x, y, z: case_shape.isInside(
            App.Vector(x, y, z),
            1e-7,
            True,
        )

        self.assertFalse(is_inside(0, -47.0, 17.0))
        self.assertTrue(is_inside(6.5, -47.0, 17.0))
        self.assertTrue(is_inside(0, -47.0, 20.5))
        self.assertFalse(is_inside(7.5, -47.0, 17.0))

    def test_bottom_lid_fits_inside_opening_with_four_m2_5_clearance_holes(self):
        parameters = self.document.getObject("Parameters")
        bottom_lid = self.document.getObject("BottomLid")
        case_shape = self.document.getObject("RoundCase").Shape

        self.assertAlmostEqual(parameters.BottomLidThickness.Value, 3.0)
        self.assertAlmostEqual(parameters.LidScrewHoleDiameter.Value, 2.8)
        self.assertTrue(bottom_lid.Shape.isValid())
        self.assertEqual(len(bottom_lid.Shape.Solids), 1)
        self.assertAlmostEqual(bottom_lid.Shape.BoundBox.XLength, 99.6)
        self.assertAlmostEqual(
            (parameters.InternalDiameter.Value - bottom_lid.Shape.BoundBox.XLength) / 2,
            0.2,
        )

        is_inside = lambda x, y, z: bottom_lid.Shape.isInside(
            App.Vector(x, y, z),
            1e-7,
            True,
        )
        self.assertTrue(is_inside(0, 0, 1.0))
        self.assertTrue(is_inside(0, 0, 2.5))
        self.assertFalse(is_inside(0, 0, -0.5))
        self.assertTrue(is_inside(49.7, 0, 1.0))
        self.assertFalse(is_inside(49.9, 0, 1.0))
        self.assertLess(case_shape.common(bottom_lid.Shape).Volume, 1e-7)
        for x, y in ((0, -46.8), (46.8, 0), (0, 46.8), (-46.8, 0)):
            radius = math.hypot(x, y)
            self.assertFalse(is_inside(x, y, 1.0))
            self.assertTrue(is_inside(x - 2.0 * x / radius, y - 2.0 * y / radius, 1.0))

    def test_bottom_lid_uses_90_degree_m2_5_countersinks(self):
        parameters = self.document.getObject("Parameters")
        bottom_lid = self.document.getObject("BottomLid")

        self.assertAlmostEqual(parameters.LidCountersinkDiameter.Value, 5.2)
        self.assertAlmostEqual(parameters.LidCountersinkDepth.Value, 1.2)

        is_inside = lambda x, y, z: bottom_lid.Shape.isInside(
            App.Vector(x, y, z),
            1e-7,
            True,
        )
        self.assertFalse(is_inside(49.2, 0, 0.1))
        self.assertTrue(is_inside(49.2, 0, 1.3))
        self.assertFalse(is_inside(48.1, 0, 2.5))
        self.assertTrue(is_inside(48.3, 0, 2.5))

    def test_case_has_four_screw_bosses_with_pilot_holes(self):
        parameters = self.document.getObject("Parameters")
        case_shape = self.document.getObject("RoundCase").Shape

        self.assertAlmostEqual(parameters.ScrewBossDiameter.Value, 7.0)
        self.assertAlmostEqual(parameters.ScrewBossHeight.Value, 8.0)
        self.assertAlmostEqual(parameters.ScrewPilotHoleDiameter.Value, 2.2)
        self.assertAlmostEqual(parameters.ScrewCircleRadius.Value, 46.8)
        self.assertTrue(case_shape.isValid())
        self.assertEqual(len(case_shape.Solids), 1)

        is_inside = lambda x, y, z: case_shape.isInside(
            App.Vector(x, y, z),
            1e-7,
            True,
        )
        self.assertFalse(is_inside(0, 0, 4.0))
        for x, y in ((0, -46.8), (46.8, 0), (0, 46.8), (-46.8, 0)):
            radius = math.hypot(x, y)
            ring_x = x - 2.0 * x / radius
            ring_y = y - 2.0 * y / radius
            self.assertFalse(is_inside(x, y, 4.0))
            self.assertFalse(is_inside(ring_x, ring_y, 2.5))
            self.assertTrue(is_inside(ring_x, ring_y, 4.0))

    def test_battery_and_development_board_fit_side_by_side_without_case_collision(self):
        parameters = self.document.getObject("Parameters")
        case_shape = self.document.getObject("RoundCase").Shape
        battery = self.document.getObject("BatteryEnvelope").Shape
        board = self.document.getObject("DevelopmentBoardEnvelope").Shape

        self.assertAlmostEqual(parameters.InternalDiameter.Value, 100.0)
        self.assertAlmostEqual(parameters.OuterDiameter.Value, 104.0)
        self.assertAlmostEqual(parameters.InternalHeight.Value, 34.0)
        self.assertAlmostEqual(battery.BoundBox.XLength, 70.0)
        self.assertAlmostEqual(battery.BoundBox.YLength, 56.0)
        self.assertAlmostEqual(battery.BoundBox.ZLength, 19.0)
        self.assertAlmostEqual(board.BoundBox.XLength, 64.0)
        self.assertAlmostEqual(board.BoundBox.YLength, 13.0)
        self.assertAlmostEqual(board.BoundBox.ZLength, 28.4)
        self.assertAlmostEqual(battery.BoundBox.ZMin, 3.0)
        self.assertAlmostEqual(battery.BoundBox.ZMax, 22.0)
        self.assertAlmostEqual(battery.BoundBox.YMin, -21.915, places=3)
        self.assertAlmostEqual(battery.BoundBox.YMax, 34.085, places=3)
        self.assertAlmostEqual(board.BoundBox.YMin, -36.915, places=3)
        self.assertAlmostEqual(board.BoundBox.YMax, -23.915, places=3)
        self.assertAlmostEqual(board.BoundBox.ZMin, 3.0)
        self.assertAlmostEqual(board.BoundBox.ZMax, 31.4)
        self.assertLess(case_shape.common(battery).Volume, 1e-7)
        self.assertLess(case_shape.common(board).Volume, 1e-7)
        self.assertAlmostEqual(battery.distToShape(board)[0], 2.0)
        self.assertAlmostEqual(parameters.InternalHeight.Value - board.BoundBox.ZMax, 2.6)

    def test_bottom_lid_has_short_battery_locating_rails(self):
        bottom_lid = self.document.getObject("BottomLid")
        is_inside = lambda x, y, z: bottom_lid.Shape.isInside(
            App.Vector(x, y, z),
            1e-7,
            True,
        )

        self.assertTrue(is_inside(0, 34.9, 4.0))
        self.assertTrue(is_inside(0, -23.0, 4.0))
        self.assertTrue(is_inside(35.9, 0, 4.0))
        self.assertTrue(is_inside(-35.9, 0, 4.0))
        self.assertFalse(is_inside(0, 34.0, 4.0))
        self.assertFalse(is_inside(0, -21.5, 4.0))
        self.assertFalse(is_inside(35.0, 0, 4.0))

    def test_bottom_lid_has_side_board_retaining_slot(self):
        bottom_lid = self.document.getObject("BottomLid")
        board = self.document.getObject("DevelopmentBoardEnvelope").Shape
        is_inside = lambda x, y, z: bottom_lid.Shape.isInside(
            App.Vector(x, y, z),
            1e-7,
            True,
        )

        self.assertTrue(is_inside(0, -37.865, 8.0))
        self.assertTrue(is_inside(0, -22.965, 8.0))
        self.assertTrue(is_inside(32.95, -30.415, 8.0))
        self.assertTrue(is_inside(-32.95, -30.415, 8.0))
        self.assertFalse(is_inside(0, -30.415, 8.0))
        self.assertFalse(is_inside(31.8, -30.415, 8.0))
        self.assertLess(bottom_lid.Shape.common(board).Volume, 1e-7)


if __name__ == "__main__":
    unittest.main()
