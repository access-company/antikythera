# Contributing Guide

As an ever-expanding application platform, antikythera is always accepting contributions.

Here, contributions can be of several forms:

- Asking questions
- Finding bugs
- Making feature suggestions
- Committing code
- Improving documentations

All of them are helpful! Follow the guidelines provided here.

## Surveying and Discussions

- First, read up [documentations](https://hexdocs.pm/antikythera) before asking questions/making suggestions.
- Also, search in [antikythera API reference](https://hexdocs.pm/antikythera/api-reference.html)
  to find detailed information about modules/functions.
- Make sure you are using latest antikythera with latest supported Erlang/Elixir version.
    - Refresh dependencies if dependency/compile related error occurred:

      ```
      $ mix deps.clean
      $ mix deps.update --all
      $ mix deps.get
      ```

- If you need further help, found bug in antikythera code, or came up with feature suggestions, follow the steps below.

### Post in [Antikythera Framework Users Mailing List (Users ML)](https://groups.google.com/forum/#!forum/antikythera_users)

- Your problem might already be encountered and solved by other developers, and they could offer you a help.
    - Even if they have not solved the problem, they may still be able to provide additional information,
      which can be quite useful for bug fixes.
- If your problem is just an oversight or an error, it can be solved here.
- Discussions in the Users ML can be referenced in the future, making it an effective knowledge base.
- If the problem is reported to ML first, other developers can recognize the problem and reduce their cognitive load.
- For feature suggestions:
    - Other developers can agree/disagree/reinforce/provide additional points to your suggestions.
    - Core developers can respond with design philosophies/decisions behind antikythera development,
      and provide proper directions to your suggestion:
        - Implement it as a new feature
        - Achieve it with existing features
        - Not going to support as an antikythera feature
- If you think your mail is not getting attentions, reply to the thread to request answers.
  People just might have overlooked the mail.
    - Or, your post might be too trivial to get answered. Make sure you check out documentations mentioned in the previous section.
- If you are working closely to the core developer team, you MAY just tell your concern to them and open an issue.
    - But, as described above, posting a mail to Users ML is itself beneficial to the whole antikythera community, so it is preferred.

### Report in [Issue Tracker](https://github.com/access-company/antikythera/issues)

- If your problem is indeed marked as a bug, or your feature suggestions are accepted,
  you or one of core developers can open issues.
- If you are absolutely certain that you found a bug, you MAY just report an issue directly.
    - However, dropping a descriptive mail in Users ML is always helpful and preferred.
- **DO NOT** make feature issues directly. Discuss in ML first.
    - This is to keep backlog as small and manageable as possible.
    - If feature issues are randomly opened, core developers must periodically review and organize them, which is costly.

### Mail and Issue manners

- Try to be as descriptive as possible.
    - **NOT** just "I can not do XXX" or "It says YYY on compile".
    - These information are essential:
        - What are you going to achieve? (And Why?)
        - What changes/circumstances cause the problem?
        - What does the compiler/log say?
        - Which version(commit hash) of antikythera you use?
        - Can you reproduce it and how?
    - (Not all of them are always required, but they surely make your posts more descriptive)

## Contributing to the antikythera code

- Reported issues are evaluated by their urgency and assigned/tagged appropriately.
- Basically those issues are assigned to core developers and implemented.
  However, it is welcomed to make your own effort to pick up one of them and implement it.
    - Just drop comments in the issue you are willing to tackle with.
      Then the core team will assign it to you.
- If you try to implement features, follow the instruction explained in this section.

### Developing

- Fork this repository and setup antikythera project:

  ```
  $ cd path/to/antikythera/
  $ mix deps.get
  $ mix test
  ```

- After you have made sure that you can run antikythera tests, check out a feature branch from `master` branch.
    - Antikythera and its related projects use [GitHub-flow](http://scottchacon.com/2011/08/31/github-flow.html);
      anything on `master` are automatically tested (though it is not actually "deployed" to somewhere).
    - For branch name and commit messages, look up recent branches/commits and follow their conventions
      (be sufficiently descriptive and simple).
- Implement the feature with tests.
    - At least, test behavior of public interfaces of the modules,
      [as advised by Elixir author, José Valim](http://stackoverflow.com/a/20949676/5421126).
    - Always confirm that the whole test passes.
      [`mix test.watch`](https://github.com/lpil/mix-test.watch) is useful to monitor file changes and automatically run the test.
    - If your change requires an actual gear for testing, see the next section.
- Implement by a (relatively) small chunk.
    - Your feature might require quite a large addition or changes.
    - Such a large patch is hard to read and review, leads to blocking of reviewers' activities.
    - Keep your components (modules/functions) loosely-coupled and follow the single responsibility principle,
      so that they can be implemented/tested separately, thus can be reviewed/merged steadily.
- Make use of our [style guide](https://github.com/access-company/antikythera/blob/master/STYLE_GUIDE.md).

#### Use `testgear` for testing antikythera's features

- Sometimes it is essential to test features through an actual gear.
    - For example, when you implement a new [`Plug`](./lib/web/controller/plug.ex).
    - Or, your implementation touches existing codes and might break current functionalities.
- In such cases, we use [`testgear`](https://github.com/access-company/testgear) and
  [`antikythera_instance_example`](https://github.com/access-company/antikythera_instance_example)
- Since these are separate projects, you will likely write tests using `testgear` as a separate step from implementing features in antikythera.
- Fork `testgear` repository and setup like the following:

  ```
  $ cd path/to/testgear/
  $ export ANTIKYTHERA_INSTANCE_DEP='{:antikythera_instance_example, [git: "git@github.com:access-company/antikythera_instance_example.git"]}'
  $ mix deps.get
  $ mix deps.get                      # Fetch dev/test-only dependencies declared in antikythera_instance_example
  $ mix test                          # Whitebox test
  $ iex -S mix
  (from another terminal)
  $ export ANTIKYTHERA_INSTANCE_DEP='{:antikythera_instance_example, [git: "git@github.com:access-company/antikythera_instance_example.git"]}'
  $ TEST_MODE=blackbox_local mix test # Blackbox test
  ```

- Then, you set up a controller that uses new feature, and test its integrity via request and response.
    - Consult [the document for testing in gears](https://hexdocs.pm/antikythera/testing.html) as a reference.

### Pull Request

- Branches are Pull Requested against (mostly) `master` branch, then reviewed by core team, and merged when approved by **ALL MEMBERS**.
- When you are confident about your development chunk, prepare your Pull Request.
    - First, you **MUST** self-review the changes you made in the branch. This is particularly important.
        - Follow the coding conventions described in the [style guide](https://github.com/access-company/antikythera/blob/master/STYLE_GUIDE.md).
        - Make sure your code fit in existing antikythera code.
    - Provide sufficient `@moduledoc`, `@doc` and `@typedoc`, especially if it is publicly available.
    - If your code contains workaround or hacky solution, put an explanation comments.
    - Check typo, mis-indentations, mis-alignments, trailing white spaces or extra blank lines. Utilize your editor functionalities.
    - Run the Dialyzer (`$ mix dialyzer`) and fix any errors reported.
    - If reviewers deemed the Pull Request is not self-reviewed well, it CAN be rejected.
- When you are confident on your branch, push it to your fork repository, then open Pull Request.
    - Pull Request title can be just branch name, or summarized description.
    - Make sure the Pull Request and the issue are mutually linked.
- When your Pull Request is ready, you **MUST** post description either in the Pull Request itself, or in the issue.
    - In the description:
        - Briefly state what is implemented in the patch (no need to explain procedures step by step, just outline).
        - If the patch is incomplete and a part of the whole feature, make sure what part of the feature is implemented
          and how it works in the whole picture (and optionally, what is not yet implemented and what comes in next chunk).
        - If you think some part of the patch is hard to understand, any additional notes will be helpful for reviewers.

### Review and Merge

- For each comments made by reviewers, you **MUST**:
    - Fix the specified error/style/logic/etc..., OR,
    - Explain decision factor/reason behind code, and discuss, THEN,
    - Fix, leave as-is or put comments on that part, AND FINALLY,
    - Reply to the comments with fixing commit hash, or closing words (e.g. "Addressed in \<commit hash\>" or "As discussed above, we keep this as-is").
- When all reviewers approved the Pull Request, one of core developers will take care of the rest:
    - The branch will be merged with "squash" (in most cases from GitHub UI, i.e. "button merge").
        - In squash merge commit, `Author` is the contributor, and `Committer` is a member who performed the merge.
          So be assured that your contributions are always properly counted!
        - When successfully merged, remote branch can be safely deleted (for your fork repository branches, it is up you).
    - When the new `master` is successfully tested:
        - If the issue is solved/the feature is fully implemented, it will be closed. Thanks for your contribution!
        - If the issue is still in progress, you resume your development.
    - Sometimes tests can fail due to unexpected side effects or errors.
        - You can tackle with fixing it, but in most cases core team will take care of such complicated failures.
