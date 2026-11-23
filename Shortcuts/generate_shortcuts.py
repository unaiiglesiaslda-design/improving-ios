#!/usr/bin/env python3
"""
Generates 100% Apple-native unsigned .shortcut XML property lists for Improving iOS:
  1. Sync Improving (1 Toque).xml     -> Copies Health JSON to clipboard & opens improving://sync?source=clipboard
  2. Sync Improving (Automatico).xml  -> Saves health_sync.json silently in background for Personal Automations

Uses ONLY built-in Apple Shortcuts actions (`is.workflow.actions.*`), so it works regardless
of sideload Bundle ID renaming (AltStore / SideStore / Sideloadly) and requires ZERO paid Apple Developer entitlements!
"""

import os
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


def find_health_samples_action(action_uuid: str, sample_type_label: str, days_back: int) -> dict:
    return {
        "WFWorkflowActionIdentifier": "is.workflow.actions.filter.health.quantity",
        "WFWorkflowActionParameters": {
            "UUID": action_uuid,
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
        },
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


def build_common_health_actions(variant: str):
    """Builds the 8 Find Health Samples blocks + Get Details + unified Dictionary action."""
    metrics = [
        # (key_prefix, ActionKit English picker label, days_back, include_end_date)
        ("hr", "Heart Rate", 2, False),
        ("hrv", "Heart Rate Variability", 7, False),
        ("rhr", "Resting Heart Rate", 7, False),
        ("sleep", "Sleep", 3, True),
        ("resp", "Respiratory Rate", 7, False),
        ("spo2", "Blood Oxygen", 7, False),
        ("steps", "Steps", 3, False),
        ("kcal", "Active Calories", 3, False),
    ]

    actions = []
    dict_items = []

    for prefix, label, days, include_end in metrics:
        find_id = make_uuid(f"{variant}.{prefix}.find")
        val_id = make_uuid(f"{variant}.{prefix}.val")
        start_id = make_uuid(f"{variant}.{prefix}.start")

        actions.append(find_health_samples_action(find_id, label, days))
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


def build_one_tap_shortcut() -> dict:
    actions, dict_id = build_common_health_actions("onetap")

    clip_id = make_uuid("onetap.clipboard")
    url_id = make_uuid("onetap.url")
    open_id = make_uuid("onetap.openurl")

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
    return wrap_workflow("Sync Improving (1 Toque)", actions, glyph=61440, color=431817727)


def build_background_file_shortcut() -> dict:
    actions, dict_id = build_common_health_actions("autofile")

    rename_id = make_uuid("autofile.setname")
    save_id = make_uuid("autofile.savefile")

    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.setitemname",
            "WFWorkflowActionParameters": {
                "UUID": rename_id,
                "WFInput": token_attachment(dict_id, "Dictionary"),
                "WFName": "health_sync.json",
                "WFDontIncludeFileExtension": True,
            },
        }
    )
    actions.append(
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.documentpicker.save",
            "WFWorkflowActionParameters": {
                "UUID": save_id,
                "WFInput": token_attachment(rename_id, "Renamed Item"),
                "WFAskWhereToSave": False,
                "WFSaveFileOverwrite": True,
                "WFFileDestinationPath": "health_sync.json",
            },
        }
    )
    return wrap_workflow("Sync Improving (Automático)", actions, glyph=59714, color=4292093695)


def main():
    out_dir = Path(__file__).resolve().parent / "generated"
    out_dir.mkdir(parents=True, exist_ok=True)

    outputs = [
        ("Sync-Improving-1-Toque.xml", build_one_tap_shortcut()),
        ("Sync-Improving-Automatico.xml", build_background_file_shortcut()),
    ]
    for filename, wf in outputs:
        xml_path = out_dir / filename
        with open(xml_path, "wb") as f:
            plistlib.dump(wf, f, fmt=plistlib.FMT_XML, sort_keys=True)
        print(f"Generated: {xml_path} ({xml_path.stat().st_size} bytes, {len(wf['WFWorkflowActions'])} actions)")


if __name__ == "__main__":
    main()
