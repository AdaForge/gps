"""
This file provides support for gnathub.
"""

import GPS
import gps_utils
import os_utils

gnathub_menu = "/Gnathub/Run "
tools = ['codepeer', 'gcov', 'gnatcoverage', 'gnatcheck', 'gnatmetric',
         'gnatprove']


def register_menu(tool):
    @gps_utils.interactive(category="Gnathub",
                           menu=gnathub_menu+tool,
                           name="Run gnathub: " + tool)
    def action():
        target = GPS.BuildTarget("gnathub")
        target.execute(extra_args="--incremental --plugins=" + tool,
                       synchronous=False)

XML = r"""<?xml version="1.0" ?>
<GPS>
  <target-model name="gnathub">
    <iconname>call-start</iconname>
    <description>Run gnathup executable</description>
    <command-line>
      <arg>gnathub</arg>
      <arg>-P%PP</arg>
      <arg>%X</arg>
    </command-line>
    <switches command="%(tool_name)s" columns="1">
    <field label="Execute" switch="--exec="
      tip="Python script to execute (implies --incremental)"/>
    <field label="Plugins" switch="--plugins="
      tip="Comma separated list of plugins to execute"/>
    <spin label="Parallel" switch="-j"
      tip="Number of jobs to run in parallel"
      max="99" min="0" default="0"/>
    <check label="Incremental" switch="-i"
      tip="Do not remove database if exists"/>
    <check label="Quiet" switch="-q"
      tip="Toggle quiet mode on"/>
    <check label="Verbose" switch="-v"
      tip="Toggle verbose mode on"/>
    </switches>
  </target-model>

  <target name="gnathub" category="_Project_" model="gnathub">
    <launch-mode>MANUALLY_WITH_NO_DIALOG</launch-mode>
    <in-menu>FALSE</in-menu>
    <command-line>
      <arg>gnathub</arg>
      <arg>-P%PP</arg>
      <arg>%X</arg>
    </command-line>
  </target>

</GPS>
"""

# Check for gnathub executable and GNAThub module active status:

logger = GPS.Logger("MODULE.GNAThub")

if os_utils.locate_exec_on_path("gnathub") and logger.active:
    GPS.parse_xml(XML)

    for J in tools:
        register_menu(J)

    @gps_utils.hook("compilation_finished")
    def __hook(category, target="", mode="", shadow=False, background=False,
               status=0, *args):
        if not status and target == "gnathub":
            GPS.execute_action("gnathub display analysis")