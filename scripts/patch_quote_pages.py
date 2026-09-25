#!/usr/bin/env python3
"""Retrieve the live Quote and Opportunity flexipages, inject Deal analysis, and deploy.

Does not deploy Network metadata. Pass --target-org (an sf CLI alias or username).
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "unpackaged/post_ux/flexipages/RLM_Quote_Record_Page.flexipage-meta.xml"
NS = {"sf": "http://soap.sforce.com/2006/04/metadata"}
SF = "{http://soap.sforce.com/2006/04/metadata}"
ET.register_namespace("", "http://soap.sforce.com/2006/04/metadata")


def local(tag: str) -> str:
    return tag.split("}", 1)[-1]


def findall(el, name):
    return [c for c in el if local(c.tag) == name]


def find(el, name):
    for c in el:
        if local(c.tag) == name:
            return c
    return None


def make(tag, text=None):
    el = ET.Element(SF + tag)
    if text is not None:
        el.text = text
    return el


def add_action(root, after, action):
    for props in root.iter(SF + "componentInstanceProperties"):
        name = find(props, "name")
        if name is None or name.text != "actionNames":
            continue
        vlist = find(props, "valueList")
        if vlist is None:
            continue
        existing = []
        for item in findall(vlist, "valueListItems"):
            val = find(item, "value")
            if val is not None:
                existing.append(val.text)
        if action in existing:
            return
        insert_at = len(list(vlist))
        for i, item in enumerate(findall(vlist, "valueListItems")):
            val = find(item, "value")
            if val is not None and val.text == after:
                insert_at = list(vlist).index(item) + 1
                break
        new_item = make("valueListItems")
        new_item.append(make("value", action))
        children = list(vlist)
        if insert_at >= len(children):
            vlist.append(new_item)
        else:
            vlist.insert(insert_at, new_item)
        return


TLE_IDS = {
    "runtime_rca_salesTxnLineTable",
    "runtime_revenue_foundation_transactionLineTable",
}

VIEW_RAMP_FIELDS = (
    "QuoteLineItem.SegmentName",
    "QuoteLineItem.SegmentType",
    "QuoteLineItem.Quantity",
    "QuoteLineItem.StartDate",
    "QuoteLineItem.EndDate",
    "QuoteLineItem.Discount",
    "QuoteLineItem.DiscountAmount",
    "QuoteLineItem.UnitPriceUplift",
    "QuoteLineItem.NetUnitPrice",
    "QuoteLineItem.NetTotalPrice",
    "QuoteLineItem.TotalPrice",
)

GROUP_RAMP_DISPLAY_FIELDS = (
    "QuoteLineItem.QuoteLineGroup.Name[QuoteLineGroup]",
    "QuoteLineItem.QuoteLineGroup.SegmentType[QuoteLineGroup]",
    "QuoteLineItem.QuoteLineGroup.IsRamped[QuoteLineGroup]",
)


def order_display_fields(root, after, fields):
    """Place fields in this order immediately after `after`, even if they already exist."""
    patched = False
    wanted = list(fields)
    wanted_set = set(wanted)
    for ci in root.iter(SF + "componentInstance"):
        ident = find(ci, "identifier")
        if ident is None or ident.text not in TLE_IDS:
            continue
        for props in findall(ci, "componentInstanceProperties"):
            name = find(props, "name")
            if name is None or name.text != "displayFields":
                continue
            vlist = find(props, "valueList")
            if vlist is None:
                continue
            after_item = None
            for item in list(findall(vlist, "valueListItems")):
                val = find(item, "value")
                text = val.text if val is not None else None
                if text in wanted_set:
                    vlist.remove(item)
                elif text == after:
                    after_item = item
            insert_at = (
                list(vlist).index(after_item) + 1
                if after_item is not None
                else len(list(vlist))
            )
            for field in wanted:
                new_item = make("valueListItems")
                new_item.append(make("value", field))
                children = list(vlist)
                if insert_at >= len(children):
                    vlist.append(new_item)
                else:
                    vlist.insert(insert_at, new_item)
                insert_at += 1
            patched = True
    return patched


COST_EDIT_FIELDS = (
    "QuoteLineItem.UnitCost",
    "QuoteLineItem.TotalCost",
    "QuoteLineItem.TotalMargin",
    "QuoteLineItem.Margin",
)


def remove_display_fields(root, fields):
    """Sellers discount % or $ — standard Margin is an Adjustment Type, so keep it off the TLE picker."""
    drop = set(fields)
    for ci in root.iter(SF + "componentInstance"):
        ident = find(ci, "identifier")
        if ident is None or ident.text not in TLE_IDS:
            continue
        for props in findall(ci, "componentInstanceProperties"):
            name = find(props, "name")
            if name is None or name.text != "displayFields":
                continue
            vlist = find(props, "valueList")
            if vlist is None:
                continue
            for item in list(findall(vlist, "valueListItems")):
                val = find(item, "value")
                if val is not None and val.text in drop:
                    vlist.remove(item)


def find_component_instance(root, identifier):
    for ci in root.iter(SF + "componentInstance"):
        ident = find(ci, "identifier")
        if ident is not None and ident.text == identifier:
            return ci
    return None


def append_display_fields(root, fields):
    """Append TLE columns if they are not already on the table."""
    wanted = list(fields)
    for ci in root.iter(SF + "componentInstance"):
        ident = find(ci, "identifier")
        if ident is None or ident.text not in TLE_IDS:
            continue
        for props in findall(ci, "componentInstanceProperties"):
            name = find(props, "name")
            if name is None or name.text != "displayFields":
                continue
            vlist = find(props, "valueList")
            if vlist is None:
                continue
            existing = set()
            for item in findall(vlist, "valueListItems"):
                val = find(item, "value")
                if val is not None:
                    existing.add(val.text)
            for field in wanted:
                if field in existing:
                    continue
                new_item = make("valueListItems")
                new_item.append(make("value", field))
                vlist.append(new_item)
                existing.add(field)


def ensure_prop_value_list(ci, name, values):
    for props in findall(ci, "componentInstanceProperties"):
        n = find(props, "name")
        if n is None or n.text != name:
            continue
        vlist = find(props, "valueList")
        if vlist is None:
            vlist = make("valueList")
            props.append(vlist)
        existing = set()
        for item in findall(vlist, "valueListItems"):
            val = find(item, "value")
            if val is not None:
                existing.add(val.text)
        for field in values:
            if field in existing:
                continue
            new_item = make("valueListItems")
            new_item.append(make("value", field))
            vlist.append(new_item)
        return
    props = make("componentInstanceProperties")
    props.append(make("name", name))
    vlist = make("valueList")
    for field in values:
        item = make("valueListItems")
        item.append(make("value", field))
        vlist.append(item)
    props.append(vlist)
    ci.insert(0, props)


def ensure_empty_prop(ci, name):
    for props in findall(ci, "componentInstanceProperties"):
        n = find(props, "name")
        if n is not None and n.text == name:
            return
    props = make("componentInstanceProperties")
    props.append(make("name", name))
    ci.insert(0, props)


def ensure_group_ramp_tle(root):
    """Create Ramp Schedule lives on Sales Transaction Line Editor, not TLE."""
    for ci in root.iter(SF + "componentInstance"):
        ident = find(ci, "identifier")
        if ident is None or ident.text not in TLE_IDS:
            continue
        cname = find(ci, "componentName")
        if cname is not None:
            cname.text = "runtime_rca:salesTxnLineTable"
        set_ci_property(ci, "enableQuickAdd", "true")
        set_ci_property(ci, "enableSidepanel", "true")
        ensure_empty_prop(ci, "groupRampFields")
        ensure_prop_value_list(ci, "viewRampDetailFields", VIEW_RAMP_FIELDS)
    append_display_fields(root, GROUP_RAMP_DISPLAY_FIELDS)


def set_ci_property(ci, name, value):
    for props in findall(ci, "componentInstanceProperties"):
        n = find(props, "name")
        if n is not None and n.text == name:
            val = find(props, "value")
            if val is None:
                props.append(make("value", value))
            else:
                val.text = value
            return
    props = make("componentInstanceProperties")
    props.append(make("name", name))
    props.append(make("value", value))
    ci.insert(0, props)


def add_facet_component(root, facet_name, component_name, identifier, properties=None):
    """Add an LWC to an existing facet region (no-op if the facet is missing)."""
    for region in findall(root, "flexiPageRegions"):
        name = find(region, "name")
        if name is None or name.text != facet_name:
            continue
        for item in findall(region, "itemInstances"):
            ci = find(item, "componentInstance")
            ident = find(ci, "identifier") if ci is not None else None
            if ident is not None and ident.text == identifier:
                if properties:
                    for key, val in properties.items():
                        set_ci_property(ci, key, val)
                return False
        new_item = make("itemInstances")
        ci = make("componentInstance")
        if properties:
            for key, val in properties.items():
                set_ci_property(ci, key, val)
        ci.append(make("componentName", component_name))
        ci.append(make("identifier", identifier))
        new_item.append(ci)
        insert_at = 0
        for i, child in enumerate(list(region)):
            if local(child.tag) == "itemInstances":
                insert_at = i + 1
        region.insert(insert_at, new_item)
        return True
    return False


def add_header_component(root, component_name, identifier, after_identifier=None, properties=None):
    """Place an LWC in header or subheader, after path when present."""
    for region in findall(root, "flexiPageRegions"):
        rname = find(region, "name")
        if rname is None or rname.text not in ("header", "subheader"):
            continue
        for item in findall(region, "itemInstances"):
            ci = find(item, "componentInstance")
            ident = find(ci, "identifier") if ci is not None else None
            if ident is not None and ident.text == identifier:
                if properties:
                    for key, val in properties.items():
                        set_ci_property(ci, key, val)
                return False
        new_item = make("itemInstances")
        ci = make("componentInstance")
        if properties:
            for key, val in properties.items():
                set_ci_property(ci, key, val)
        ci.append(make("componentName", component_name))
        ci.append(make("identifier", identifier))
        new_item.append(ci)
        insert_at = 0
        last_item = 0
        found_after = False
        for i, child in enumerate(list(region)):
            if local(child.tag) != "itemInstances":
                continue
            last_item = i + 1
            inst = find(child, "componentInstance")
            ident = find(inst, "identifier") if inst is not None else None
            if ident is not None and after_identifier and ident.text == after_identifier:
                insert_at = i + 1
                found_after = True
                break
        if not found_after:
            insert_at = last_item
        region.insert(insert_at, new_item)
        return True
    return False


def rename_tab_title(root, identifier, title):
    for ci in root.iter(SF + "componentInstance"):
        ident = find(ci, "identifier")
        if ident is None or ident.text != identifier:
            continue
        for props in findall(ci, "componentInstanceProperties"):
            name = find(props, "name")
            val = find(props, "value")
            if name is not None and name.text == "title" and val is not None:
                val.text = title
                return


def add_facet_fields(root, after, fields):
    for region in findall(root, "flexiPageRegions"):
        items = findall(region, "itemInstances")
        for item in items:
            fi = find(item, "fieldInstance")
            if fi is None:
                continue
            field_item = find(fi, "fieldItem")
            if field_item is None or field_item.text != f"Record.{after}":
                continue
            existing = set()
            for other in items:
                ofi = find(other, "fieldInstance")
                if ofi is None:
                    continue
                ofield = find(ofi, "fieldItem")
                if ofield is not None and ofield.text:
                    existing.add(ofield.text.replace("Record.", ""))
            idx = list(region).index(item) + 1
            for field in fields:
                if field in existing:
                    continue
                new_item = make("itemInstances")
                inst = make("fieldInstance")
                prop = make("fieldInstanceProperties")
                prop.append(make("name", "uiBehavior"))
                prop.append(make("value", "none"))
                inst.append(prop)
                inst.append(make("fieldItem", f"Record.{field}"))
                inst.append(make("identifier", f"Record{field}Field"))
                new_item.append(inst)
                region.insert(idx, new_item)
                idx += 1
            return


def add_deal_health_tab(root):
    facet_name = "Facet-zebra-deal-health"
    already = False
    for region in findall(root, "flexiPageRegions"):
        name = find(region, "name")
        if name is not None and name.text == facet_name:
            already = True
            break
        if name is not None and name.text == "maintabs":
            for item in findall(region, "itemInstances"):
                ci = find(item, "componentInstance")
                ident = find(ci, "identifier") if ci is not None else None
                if ident is not None and ident.text == "dealAnalysisTab":
                    already = True
    if already:
        return

    # New facet region with the LWC
    region = make("flexiPageRegions")
    item = make("itemInstances")
    ci = make("componentInstance")
    ci.append(make("componentName", "c:rlmDealHealth"))
    ci.append(make("identifier", "c_rlmDealHealth"))
    item.append(ci)
    region.append(item)
    region.append(make("name", facet_name))
    region.append(make("type", "Facet"))

    # Insert facet before maintabs region
    children = list(root)
    insert_at = len(children)
    for i, child in enumerate(children):
        if local(child.tag) == "flexiPageRegions" and find(child, "name") is not None:
            if find(child, "name").text == "maintabs":
                insert_at = i
                tab_item = make("itemInstances")
                tab_ci = make("componentInstance")
                p1 = make("componentInstanceProperties")
                p1.append(make("name", "body"))
                p1.append(make("value", facet_name))
                p2 = make("componentInstanceProperties")
                p2.append(make("name", "title"))
                p2.append(make("value", "Deal analysis"))
                tab_ci.append(p1)
                tab_ci.append(p2)
                tab_ci.append(make("componentName", "flexipage:tab"))
                tab_ci.append(make("identifier", "dealAnalysisTab"))
                tab_item.append(tab_ci)
                # insert after Quote Lines tab (first item)
                items = findall(child, "itemInstances")
                if items:
                    child.insert(list(child).index(items[0]) + 1, tab_item)
                else:
                    child.insert(0, tab_item)
                break
    root.insert(insert_at, region)


def patch(tree: ET.ElementTree) -> None:
    root = tree.getroot()
    add_action(root, "BrowseCatalog", "CreateRampSchedule")
    add_action(root, "DeepCloneAction", "Quote.RLM_New_Price_Concession")
    add_action(root, "Quote.RLM_Submit_for_Approval", "Quote.RLM_Submit_Price_Concession")
    ensure_group_ramp_tle(root)
    add_facet_fields(
        root,
        "Description",
        [
            "RLM_PC_Justification__c",
            "PartnerAccountId",
            "AppliedDiscount",
            "RLM_Deal_Motion__c",
            "RLM_Deal_Health_Status__c",
            "RLM_Blended_Margin__c",
        ],
    )
    remove_display_fields(
        root,
        COST_EDIT_FIELDS + ("QuoteLineItem.RLM_Change_Type__c",),
    )
    order_display_fields(
        root,
        "QuoteLineItem.ListPrice",
        [
            "QuoteLineItem.RLM_Change__c",
            "QuoteLineItem.RLM_Margin_Flag__c",
            "QuoteLineItem.RLM_Line_Margin__c",
            "QuoteLineItem.Discount",
            "QuoteLineItem.DiscountAmount",
        ],
    )
    add_deal_health_tab(root)
    rename_tab_title(root, "dealAnalysisTab", "Deal analysis")
    add_header_component(
        root, "c:rlmPathBrand", "c_rlmPathBrand",
        "runtime_sales_pathassistant_pathAssistant",
    )
    add_header_component(
        root, "c:rlmDealAnalysis", "c_rlmDealAnalysis",
        "c_rlmPathBrand",
        properties={"showPrompts": "true", "showCompare": "false"},
    )
    add_facet_component(
        root,
        "Facet-zebra-deal-health",
        "c:rlmDealAnalysis",
        "c_rlmDealAnalysisCompare",
        properties={"showPrompts": "false", "showCompare": "true"},
    )


def strip_missing_quote_account(root):
    """This org has no Quote.QuoteAccountId (AccountId is derived)."""
    for region in list(findall(root, "flexiPageRegions")):
        for item in list(findall(region, "itemInstances")):
            fi = find(item, "fieldInstance")
            if fi is None:
                continue
            field_item = find(fi, "fieldItem")
            if field_item is not None and field_item.text == "Record.QuoteAccountId":
                region.remove(item)


def retrieve_live_page(org: str, dest: Path, member: str):
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "sfdx-project.json").write_text(
        '{"packageDirectories":[{"path":"force-app","default":true}],'
        '"name":"deal-desk-flexi-retrieve","sourceApiVersion":"67.0"}\n'
    )
    (dest / "force-app" / "main" / "default").mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [
            "sf", "project", "retrieve", "start",
            "--metadata", f"FlexiPage:{member}",
            "--target-org", org,
            "--wait", "10",
        ],
        cwd=str(dest),
    )
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)
    matches = list(dest.rglob(f"{member}.flexipage-meta.xml"))
    if not matches:
        raise SystemExit(f"Retrieve did not return {member}")
    return matches[0]


def patch_opportunity(tree: ET.ElementTree) -> None:
    root = tree.getroot()
    add_header_component(
        root, "c:rlmPathBrand", "c_rlmPathBrand",
        "runtime_sales_pathassistant_pathAssistant",
    )
    add_header_component(
        root, "c:rlmDealAnalysis", "c_rlmDealAnalysis",
        "c_rlmPathBrand",
        properties={"showPrompts": "true", "showCompare": "true"},
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-org", required=True)
    parser.add_argument("--no-deploy", action="store_true")
    args = parser.parse_args()
    quote_pages = ["RLM_MFG_Quote_Record_Page", "RLM_Quote_Record_Page"]
    with tempfile.TemporaryDirectory(prefix="deal-desk-flexi-") as tmp:
        tmp_path = Path(tmp)
        dest_dir = tmp_path / "force-app" / "main" / "default" / "flexipages"
        dest_dir.mkdir(parents=True, exist_ok=True)
        patched = 0
        for member in quote_pages:
            try:
                src = retrieve_live_page(
                    args.target_org, tmp_path / f"retrieve-{member}", member
                )
            except SystemExit as exc:
                print(f"Skipping {member}: {exc}")
                continue
            tree = ET.parse(src)
            strip_missing_quote_account(tree.getroot())
            patch(tree)
            dest = dest_dir / f"{member}.flexipage-meta.xml"
            tree.write(dest, encoding="UTF-8", xml_declaration=True)
            print(f"Patched Quote page written to {dest}")
            patched += 1
        try:
            opp_src = retrieve_live_page(
                args.target_org, tmp_path / "retrieve-opp", "RLM_Opportunity_Record_Page"
            )
            opp_tree = ET.parse(opp_src)
            patch_opportunity(opp_tree)
            opp_dest = dest_dir / "RLM_Opportunity_Record_Page.flexipage-meta.xml"
            opp_tree.write(opp_dest, encoding="UTF-8", xml_declaration=True)
            print(f"Patched Opportunity page written to {opp_dest}")
            patched += 1
        except SystemExit as exc:
            print(f"Skipping Opportunity page patch: {exc}")
        if patched == 0:
            raise SystemExit("No flexipages were retrieved. Check the page names in the target org.")
        (tmp_path / "sfdx-project.json").write_text(
            '{"packageDirectories":[{"path":"force-app","default":true}],'
            '"name":"deal-desk-flexi","sourceApiVersion":"67.0"}\n'
        )
        if not args.no_deploy:
            proc = subprocess.run(
                [
                    "sf", "project", "deploy", "start",
                    "--source-dir", str(tmp_path / "force-app"),
                    "--target-org", args.target_org,
                    "--wait", "20",
                ],
                cwd=tmp_path,
            )
            if proc.returncode != 0:
                sys.exit(proc.returncode)
            print("Deployed quote and opportunity pages with Deal analysis.")


if __name__ == "__main__":
    main()
