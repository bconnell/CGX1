# Prototype Test Record Template

[Documentation index](README.md) · [Prototype build](PROTOTYPE_BUILD.md) · [Validation](VALIDATION.md)

Use one record per repeatable test configuration. Do not mix analytical values with measurements in the result fields.

## Identification

| Field | Value | Notes |
|---|---|---|
| Prototype revision |  | Card/dock/controller revision |
| Test date/time |  | Include timezone |
| Operator |  |  |
| Test procedure revision |  | Link or commit |
| Source commit |  | Git commit used for firmware/software |
| Instrument set |  | List model/asset identifiers |
| Calibration status |  | Current / expired / unknown |

## Environment

| Measurement | Value | Units/notes |
|---|---:|---|
| Ambient temperature |  | °C |
| Ambient humidity |  | % RH |
| Coolant type |  | Exact product/mix |
| Coolant fill age |  |  |
| Hose configuration |  | Length, ID/OD |
| Radiator fan configuration |  | Model, RPM/PWM |
| Pump configuration |  | Model, RPM/PWM |

## Electrical

| Measurement | Value | Units/notes |
|---|---:|---|
| Host slot voltage |  | V |
| Host slot current |  | A |
| Host slot power |  | W |
| External input voltage |  | V |
| External input current |  | A |
| External input power |  | W |
| Test load |  | W |

## Thermal and coolant

| Measurement | Value | Units/notes |
|---|---:|---|
| Coolant inlet |  | °C |
| Coolant outlet |  | °C |
| Measured coolant rise |  | °C |
| Coolant flow |  | L/min |
| Simulated package/cold plate sensor |  | °C |
| VRM/regulator region |  | °C |
| Pump speed |  | RPM |
| Radiator fan speed |  | RPM |

## Fault test

Record the event, detection delay, state transition, slot power during/after transition, and whether the system remained electrically stable.

Required P0 fault cases include:

- external 48 V removed in P3/P4;
- coolant flow removed in P3/P4;
- package over temperature input;
- regulator over temperature input;
- controller hardware fault input.

## Result

**Pass/fail:**  

**Acceptance requirement:**  

**Measured result:**  

**Observed anomalies:**  

**Artifacts:** photos, logs, oscilloscope captures, thermal images, data files, or other evidence associated with this record.
