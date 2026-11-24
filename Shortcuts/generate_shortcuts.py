#!/usr/bin/env python3
"""
Generates ONE single, complete, 100% Apple-native unsigned .shortcut XML property list
for Improving iOS:

  Sync Improving (`Sync-Improving.xml` -> signed on macOS as `Sync-Improving.shortcut`)

Design goals:
- ONE master shortcut forever (no split between "1 Toque" vs "Automático"!).
- Uses ONLY verified native Apple Shortcuts `Find Health Samples` (`is.workflow.actions.filter.health.quantity`)
  HealthKit sample types that exist in iOS 16/17/18/26 (NEVER invalid types like "Workouts" that halt Shortcuts!).
- Collects ALL 18 HealthKit metrics natively exposed by Apple Shortcuts:
    Heart Rate (3d, Latest First, cap 1500 for instant live stress, HR zones Z0-Z5, auto-detected workouts & 1-min HRR),
    Heart Rate Variability (30d), Resting Heart Rate (30d), Sleep stages (14d with Start+End),
    Respiratory Rate (30d), Blood Oxygen (30d), Body Temperature (30d),
    Steps (60d/Day), Active Calories (60d/Day), VO2 Max (180d),
    Walking + Running Distance (60d/Day), Cycling Distance (60d/Day), Swimming Distance (60d/Day),
    Flights Climbed (60d/Day), Weight (90d), Body Fat Percentage (90d), Lean Body Mass (90d),
    Blood Glucose (30d).
- Delivers the complete live JSON immediately via Clipboard + `improving://sync?source=clipboard`
  so Improving updates right on the spot (< 2s) with ZERO folder-bookmark bugs and ZERO paid Apple Developer account!
"""

import plistlib
import uuid
from pathlib import Path


def make_uuid(seed: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"com.improving.health.shortcut.{seed}")).upper()


def token_attachment(output_uuid: str, output_name: str) -> dict:
    return {
        "Value": {
            "OutputName": output_name,
            "OutputUUID": output_uuid,
            "Type": "ActionOutput",
        },
        "WFSerializationType": "WFTextTokenAttachment",
    }


def token_string_from_output(output_uuid: str, output_name: str) -> dict:
    return {
        "Value": {
            "attachmentsByRange": {
                "{0, 1}": {
                    "OutputName": output_name,
                    "OutputUUID": output_uuid,
                    "Type": "ActionOutput",
                }
            },
            "string": "\ufffc",
        },
        "WFSerializationType": "WFTextTokenString",
    }


def plain_token_string(text: str) -> dict:
    return {
        "Value": {
            "attachmentsByRange": {},
            "string": text,
        },
        "WFSerializationType": "WFTextTokenString",
    }


def find_health_samples_action(
    action_uuid: str,
    sample_type_label: str,
    days_back: int,
    group_by: str = None,
    limit: int = None,
) -> dict:
    params = {
        "UUID": action_uuid,
        "WFContentItemSortProperty": "Start Date",
        "WFContentItemSortOrder": "Latest First",
        "WFContentItemFilter": {
            "Value": {
                "WFActionParameterFilterPrefix": 1,
                "WFContentPredicateBoundedDate": False,
                "WFActionParameterFilterTemplates": [
                    {
                        "Bounded": True,
                        "Operator": 4,  # is
                        "Property": "Type",
                        "Removable": False,
                        "Values": {
                            "Enumeration": {
                                "Value": sample_type_label,
                                "WFSerializationType": "WFStringSubstitutableState",
                            }
                        },
                    },
                    {
                        "Bounded": True,
                        "Operator": 1001,  # is in the last
                        "Property": "Start Date",
                        "Removable": False,
                        "Values": {
                            "Number": str(days_back),
                            "Unit": 16,  # NSCalendarUnitDay (days)
                        },
                    },
                ],
            },
            "WFSerializationType": "WFContentPredicateTableTemplate",
        },
    }
    if group_by:
        params["WFHKSampleFilteringGroupBy"] = group_by
        params["WFHKSampleFilteringFillMissing"] = False
    if limit is not None:
        params["WFContentItemLimitEnabled"] = True
        params["WFContentItemLimitNumber"] = int(limit)
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.filter.health.quantity",
        "WFWorkflowActionParameters": params,
    }


def get_health_detail_action(action_uuid: str, source_uuid: str, prop_name: str) -> dict:
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.properties.health.quantity",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
            "WFContentItemPropertyName": prop_name,
            "WFInput": token_attachment(source_uuid, "Health Samples"),
        },
    }


def dict_text_item(key: str, output_uuid: str, output_name: str) -> dict:
    return {
        "WFItemType": 0,  # Text
        "WFKey": plain_token_string(key),
        "WFValue": token_string_from_output(output_uuid, output_name),
    }


def build_all_health_actions(variant: str = "master"):
    """Builds all 18 verified native Apple Shortcuts HealthKit Find Samples queries + unified JSON Dictionary."""
    # (key_prefix, exact ActionKit English Type label, days_back, include_end_date, group_by, limit)
    metrics = [
        # 1. Live Heart Rate & Intraday Stress / Zones / Auto-Workout / Post-Effort HRR
        ("hr", "Heart Rate", 3, False, None, 1500),
        # 2. Core Autonomic, Vitals & Sleep (30d baselines + 14d staged sleep)
        ("hrv", "Heart Rate Variability", 30, False, None, 600),
        ("rhr", "Resting Heart Rate", 30, False, None, 120),
        ("sleep", "Sleep", 14, True, None, 600),
        ("resp", "Respiratory Rate", 30, False, None, 600),
        ("spo2", "Blood Oxygen", 30, False, None, 600),
        ("temp", "Body Temperature", 30, False, None, 120),
        # 3. Full 60-180d Fitness, Cardio Load, VO2 Max, Distance & Elevation (Day-grouped = instant!)
        ("steps", "Steps", 60, False, "Day", None),
        ("kcal", "Active Calories", 60, False, "Day", None),
        ("vo2", "VO2 Max", 180, False, None, 180),
        ("distance", "Walking + Running Distance", 60, False, "Day", None),
        ("cycling_distance", "Cycling Distance", 60, False, "Day", None),
        ("swimming_distance", "Swimming Distance", 60, False, "Day", None),
        ("flights", "Flights Climbed", 60, False, "Day", None),
        # 4. Biology, Body Composition & Metabolic Health
        ("weight", "Weight", 90, False, None, 90),
        ("body_fat", "Body Fat Percentage", 90, False, None, 90),
        ("lean_mass", "Lean Body Mass", 90, False, None, 90),
        ("glucose", "Blood Glucose", 30, False, None, 200),
    ]

    actions = []
    dict_items = []

    now_id = make_uuid(f"{variant}.generated_at")
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.date",
            "WFWorkflowActionParameters": {
                "UUID": now_id,
                "WFDateActionMode": "Current Date",
            },
        }
    )
    dict_items.append(dict_text_item("generated_at", now_id, "Date"))

    for prefix, label, days, include_end, group_by, limit in metrics:
        find_id = make_uuid(f"{variant}.{prefix}.find")
        val_id = make_uuid(f"{variant}.{prefix}.val")
        start_id = make_uuid(f"{variant}.{prefix}.start")

        actions.append(find_health_samples_action(find_id, label, days, group_by=group_by, limit=limit))
        actions.append(get_health_detail_action(val_id, find_id, "Value"))
        actions.append(get_health_detail_action(start_id, find_id, "Start Date"))

        dict_items.append(dict_text_item(f"{prefix}_values", val_id, "Value"))
        if include_end:
            end_id = make_uuid(f"{variant}.{prefix}.end")
            actions.append(get_health_detail_action(end_id, find_id, "End Date"))
            dict_items.append(dict_text_item(f"{prefix}_starts", start_id, "Start Date"))
            dict_items.append(dict_text_item(f"{prefix}_ends", end_id, "End Date"))
        else:
            dict_items.append(dict_text_item(f"{prefix}_dates", start_id, "Start Date"))

    dict_id = make_uuid(f"{variant}.dictionary")
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.dictionary",
            "WFWorkflowActionParameters": {
                "UUID": dict_id,
                "WFItems": {
                    "Value": {"WFDictionaryFieldValueItems": dict_items},
                    "WFSerializationType": "WFDictionaryFieldValue",
                },
            },
        }
    )
    return actions, dict_id


def wrap_workflow(name: str, actions: list, glyph: int = 61440, color: int = 431817727) -> dict:
    return {
        "WFWorkflowActions": actions,
        "WFWorkflowClientVersion": "2605.0.5",
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowIcon": {
            "WFWorkflowIconGlyphNumber": glyph,
            "WFWorkflowIconStartColor": color,
        },
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowName": name,
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": [],
    }


def build_master_shortcut() -> dict:
    actions, dict_id = build_all_health_actions("master")

    clip_id = make_uuid("master.clipboard")
    url_id = make_uuid("master.url")
    open_id = make_uuid("master.openurl")

    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.setclipboard",
            "WFWorkflowActionParameters": {
                "UUID": clip_id,
                "WFInput": token_attachment(dict_id, "Dictionary"),
            },
        }
    )
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.url",
            "WFWorkflowActionParameters": {
                "UUID": url_id,
                "WFURLActionURL": "improving://sync?source=clipboard",
            },
        }
    )
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.openurl",
            "WFWorkflowActionParameters": {
                "UUID": open_id,
                "WFInput": token_attachment(url_id, "URL"),
            },
        }
    )
    return wrap_workflow("Sync Improving", actions, glyph=61440, color=431817727)


def main():
    base_dir = Path(__file__).resolve().parent
    out_dir = base_dir / "generated"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Remove legacy 2-shortcut XML files so only ONE master shortcut exists
    for legacy in ("Sync-Improving-1-Toque.xml", "Sync-Improving-Automatico.xml"):
        p = out_dir / legacy
        if p.exists():
            p.unlink()

    wf = build_master_shortcut()
    xml_path = out_dir / "Sync-Improving.xml"
    with open(xml_path, "wb") as f:
        plistlib.dump(wf, f, fmt=plistlib.FMT_XML, sort_keys=True)
    print(f"Generated: {xml_path} ({xml_path.stat().st_size} bytes, {len(wf['WFWorkflowActions'])} actions)")


if __name__ == "__main__":
    main()
