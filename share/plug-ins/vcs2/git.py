import GPS
from . import core
import os
from workflows.promises import ProcessWrapper, join
import datetime


@core.register_vcs(default_status=GPS.VCS2.Status.UNMODIFIED)
class Git(core.VCS):

    @staticmethod
    def discover_working_dir(file):
        return core.find_admin_directory(file, '.git')

    def _git(self, args, block_exit=False):
        """
        Return git with the given arguments
        :param List(str) args: git arguments
        :param bool block_exit: if True, GPS won't exit while this process
            is running.
        :returntype: a ProcessWrapper
        """
        return ProcessWrapper(
            ['git', '--no-pager'] + args,
            block_exit=block_exit,
            directory=self.working_dir.path)

    def __git_ls_tree(self):
        """
        Compute all files under version control
        """
        all_files = set()
        p = self._git(['ls-tree', '-r', 'HEAD', '--name-only'])
        while True:
            line = yield p.wait_line()
            if line is None:
                GPS.Logger("GIT").log("finished ls-tree")
                yield all_files
                break
            all_files.add(GPS.File(os.path.join(self.working_dir.path, line)))

    def __git_status(self, s):
        """
        Run and parse "git status"
        :param s: the result of calling self.set_status_for_all_files
        """
        p = self._git(['status', '--porcelain', '--ignored'])
        while True:
            line = yield p.wait_line()
            if line is None:
                GPS.Logger("GIT").log("finished git-status")
                break

            if len(line) > 3:
                if line[0:2] in ('DD', 'AU', 'UD', 'UA', 'DU', 'AA', 'UU'):
                    status = GPS.VCS2.Status.CONFLICT
                else:
                    status = 0

                    if line[0] == 'M':
                        status = GPS.VCS2.Status.STAGED_MODIFIED
                    elif line[0] == 'A':
                        status = GPS.VCS2.Status.STAGED_ADDED
                    elif line[0] == 'D':
                        status = GPS.VCS2.Status.STAGED_DELETED
                    elif line[0] == 'R':
                        status = GPS.VCS2.Status.STAGED_RENAMED
                    elif line[0] == 'C':
                        status = GPS.VCS2.Status.STAGED_COPIED
                    elif line[0] == '?':
                        status = GPS.VCS2.Status.UNTRACKED
                    elif line[0] == '!':
                        status = GPS.VCS2.Status.IGNORED

                    if line[1] == 'M':
                        status = status | GPS.VCS2.Status.MODIFIED
                    elif line[1] == 'D':
                        status = status | GPS.VCS2.Status.DELETED

                # Filter some obvious files to speed things up
                if line[-3:] != '.o' and line[-5:] != '.ali':
                    s.set_status(
                        GPS.File(os.path.join(
                            self.working_dir.path, line[3:])),
                        status)

    def async_fetch_status_for_files(self, files):
        self.async_fetch_status_for_all_files(files)

    @core.run_in_background
    def async_fetch_status_for_all_files(self, extra_files=[]):
        """
        :param List(GPS.File) extra_files: files for which we need to
           set the status eventually
        """
        s = self.set_status_for_all_files()
        a = yield join(self.__git_ls_tree(), self.__git_status(s))
        f = a[0]
        f.update(extra_files)
        s.set_status_for_remaining_files(f)

    @core.run_in_background
    def __action_then_update_status(self, params, files=[]):
        """
        :param List(str) params: the "git ..." action to perform
        :param List(GPS.File) files: list of files
        """
        p = self._git(params + [f.path for f in files], block_exit=True)
        (status, output) = yield p.wait_until_terminate()
        if status:
            GPS.Console().write("git %s: %s" % (" ".join(params), output))
        else:
            yield self.async_fetch_status_for_all_files()  # update statuses

    def stage_or_unstage_files(self, files, stage):
        self.__action_then_update_status(['add' if stage else 'reset'], files)

    @core.run_in_background
    def commit_staged_files(self, message):
        yield self.__action_then_update_status(['commit', '-m', message])
        yield GPS.Hook('vcs_commit_done').run(self)

    @core.vcs_action(icon='git-commit-amend-symbolic',
                     name='git amend previous commit',
                     toolbar='Commits', toolbar_section='commits')
    def _commit_amend(self):
        """
        Commit all staged files and add these to the previous commit.
        """
        # ??? Should do nothing if the previous commit has been pushed
        # already.
        yield self.__action_then_update_status(
            ['commit', '--amend', '--reuse-message=HEAD'])
        GPS.Hook('vcs_commit_done').run(self)

    @core.run_in_background
    def async_fetch_history(self, visitor, filter):
        max_lines = filter[0]
        for_file = filter[1]
        pattern = filter[2]
        current_branch_only = filter[3]
        branch_commits_only = filter[4]

        p = self._git(
            ['log',
             # use tformat to get final newline
             '--pretty=tformat:%H@@%P@@%an@@%d@@%cD@@%s',
             '--branches' if not current_branch_only else '',
             '--tags' if not current_branch_only else '',
             '--topo-order',  # children before parents
             '--grep=%s' % pattern if pattern else '',
             '--max-count=%d' % max_lines if not branch_commits_only else '',
             '%s' % for_file.path if for_file else ''])

        children = {}   # number of children for each sha1
        result = []
        count = 0

        while True:
            line = yield p.wait_line()
            if line is None or '@@' not in line:
                GPS.Logger("GIT").log("finished git-status")
                break

            id, parents, author, branches, date, subject = line.split('@@')
            parents = parents.split()
            branches = None if not branches else branches.split(',')
            current = (id, author, date, subject, parents, branches)

            if branch_commits_only:
                for pa in parents:
                    children[pa] = children.setdefault(pa, 0) + 1

                # Count only relevant commits
                if (len(parents) > 1 or
                        branches is not None or
                        id not in children or
                        children[id] > 1):
                    count += 1

            result.append(current)
            if count >= max_lines:
                break

        GPS.Logger("GIT").log(
            "done parsing git-log (%s lines)" % (len(result), ))
        visitor.add_lines(result)

    @core.run_in_background
    def async_fetch_commit_details(self, ids, visitor):
        p = self._git(
            ['show',
             '-p' if len(ids) == 1 else '--name-only',
             '--stat' if len(ids) == 1 else '',
             '--notes',   # show notes
             '--pretty=fuller'] + ids)
        id = ""
        message = []
        header = []
        in_header = False

        def _emit():
            if id:
                visitor.set_details(
                    id, '\n'.join(header), '\n'.join(message))

        while True:
            line = yield p.wait_line()
            if line is None:
                _emit()
                break

            if line.startswith('commit '):
                _emit()
                id = line[7:]
                message = []
                header = [line]
                in_header = True

            elif in_header:
                if not line:
                    in_header = False
                    message = ['']
                else:
                    header.append(line)

            else:
                message.append(line)

    @core.run_in_background
    def async_view_file(self, visitor, ref, file):
        f = os.path.relpath(file.path, self.working_dir.path)
        p = self._git(['show', '%s:%s' % (ref, f)])
        status, output = yield p.wait_until_terminate()
        visitor.file_computed(output)

    @core.run_in_background
    def async_diff(self, visitor, ref, file):
        p = self._git(
            ['diff', '--no-prefix',
             ref, '--', file.path if file else ''])
        status, output = yield p.wait_until_terminate()
        if status == 0:
            visitor.diff_computed(output)
        else:
            GPS.Logger("GIT").log("Error computing diff: %s" % output)

    @core.run_in_background
    def async_annotations(self, visitor, file):
        info = {}   # for each commit id, the annotation
        current_id = None
        first_line = 1
        lines = []
        ids = []

        p = self._git(['blame', '--porcelain', file.path])
        while True:
            line = yield p.wait_line()
            if line is None:
                break

            if current_id is None:
                current_id = line.split(' ', 1)[0]

            elif line[0] == '\t':
                # The line of code, which we ignore
                lines.append(info[current_id])
                ids.append(current_id)
                current_id = None

            elif line.startswith('author '):
                info[current_id] = line[7:17]  # at most 10 chars

            elif line.startswith('committer-time '):
                d = datetime.datetime.fromtimestamp(
                    int(line[15:])).strftime('%Y%m%d')
                info[current_id] = '%s %10s %s' % (
                    d, info[current_id], current_id[0:7])

        visitor.annotations(file, first_line, ids, lines)
