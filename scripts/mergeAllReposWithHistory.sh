export FILTER_BRANCH_SQUELCH_WARNING=1

checkoutProject() {
  mod=$1
  branch=$2
  prj=`echo $mod | sed -e 's/-parent//'`
  # check that the branch exist otherwise branch=master
  [ -z "$branch" ] && branch=master
  [ $branch != master ] && curl --output /dev/null --silent --head --fail "https://github.com/vaadin/$prj/tree/$branch" || branch=master
  echo cloning $prj branch=$branch into $mod
  rm -rf $mod
  git clone -q git@github.com:vaadin/$prj.git --branch $branch $mod || exit 1
}

rewriteHistory() {
  mod=$1
  prj=`echo $mod | sed -e 's,-flow-parent,,'`
  read -r -d '' renameFiles <<EOF
    renameModule() {
      mod=\$1
      old=\$2
      new=\$3
      [ ! -d "\$old" ] && return
      [ -d \$mod/\$new ] && rm -rf \$mod/\$new
      mv \$old \$mod/\$new
      [ -f \$mod/\$new/pom.xml ] && perl -pi -e "s,>\$old<,>\$new<,g" \$mod/pom.xml \$mod/\$new/pom.xml
    }
      
    mod=$mod
    prj=$prj
    [ -z "\$mod" ] && exit 1
    mkdir -p \$mod
    for i in .??* *
    do
      [ -f "\$i" ] && mv \$i \$mod/
    done
    renameModule \$mod \$prj-flow-testbench \$prj-testbench
    renameModule \$mod \$prj-integration-tests \$prj-flow-integration-tests
    renameModule \$mod addon \$prj-flow
    renameModule \$mod examples \$prj-flow-demo
    renameModule \$mod integration-test \$prj-flow-integration-tests
    renameModule \$mod testbench \$prj-testbench
    renameModule \$mod documentation documentation
    renameModule \$mod \$prj-flow \$prj-flow
    renameModule \$mod \$prj-flow-demo \$prj-flow-demo
    renameModule \$mod \$prj-flow-integration-tests \$prj-flow-integration-tests
    renameModule \$mod \$prj-testbench \$prj-testbench
    rm -rf \$mod/.git*
    rm -rf \$mod/.travis*
    true 
EOF
  read -r -d '' renameLinks <<EOF
    mod=$mod
    prj=$prj
    repo=vaadin/\$prj-flow
    msg=\`cat -\`
    head=\`echo "\$msg" | head -1 | perl -pe 's, *\((#\d+)\) *\$,\n'\$repo'\$1,' | perl -pe 's, +(#\d{1\,3})\$,\n'\$repo'\$1,' \`
    body=\`echo "\$msg" | tail +2 | perl -pe 's,(fixes|fix):? *(#\d+),Fixes: $2,ig' | perl -pe 's,[ \():](#\d+),'\$repo'\$1,g'\`
    echo "\$head\n\$body\n\nWeb-component: $prj" | perl -p0e 's,\n\n\n+,\n\n,g'
    true
EOF
  git filter-branch -f \
     --tree-filter "$renameFiles" \
     --msg-filter "$renameLinks" \
     --prune-empty
}

compressGit() {
  git reflog expire --expire=now --all && git gc --aggressive --prune=now
}

removeBigCommits() {
  curl -s -o /tmp/bfg.jar https://repo1.maven.org/maven2/com/madgag/bfg/1.13.0/bfg-1.13.0.jar
  java -jar /tmp/bfg.jar --strip-blobs-bigger-than 160K --private 
}

createNewRepo() {
  git init
  git commit --allow-empty -m "chore: initialize vaadin-flow-components repository"
}

mergeModule() {
  mod=$1
  prj=`echo $mod | sed -e 's/-parent//'`
  component=`echo $mod | sed -e 's/-flow-parent//'`

  echo "merging $prj $component $mod"
  git remote add $component-origin ../$mod
  git pull --no-edit --quiet --allow-unrelated-histories -X theirs $component-origin master
  git remote rm $component-origin
}

modules="
vaadin-accordion-flow-parent
vaadin-avatar-flow-parent
vaadin-app-layout-flow-parent
vaadin-button-flow-parent
vaadin-checkbox-flow-parent
vaadin-combo-box-flow-parent
vaadin-context-menu-flow-parent
vaadin-custom-field-flow-parent
vaadin-date-picker-flow-parent
vaadin-date-time-picker-flow-parent
vaadin-details-flow-parent
vaadin-dialog-flow-parent
vaadin-form-layout-flow-parent
vaadin-grid-flow-parent
vaadin-icons-flow-parent
vaadin-iron-list-flow-parent
vaadin-list-box-flow-parent
vaadin-login-flow-parent
vaadin-menu-bar-flow-parent
vaadin-notification-flow-parent
vaadin-ordered-layout-flow-parent
vaadin-progress-bar-flow-parent
vaadin-radio-button-flow-parent
vaadin-select-flow-parent
vaadin-split-layout-flow-parent
vaadin-tabs-flow-parent
vaadin-text-field-flow-parent
vaadin-time-picker-flow-parent
vaadin-upload-flow-parent
vaadin-board-flow-parent
vaadin-charts-flow-parent
vaadin-confirm-dialog-flow-parent
vaadin-cookie-consent-flow-parent
vaadin-crud-flow-parent
vaadin-grid-pro-flow-parent
vaadin-rich-text-editor-flow-parent
"

# Work in a temporary folder
rm -f tmp
mkdir tmp
cd tmp || exit 1

# Checkout each component and rewrite history
for i in $modules
do
  checkoutProject $i master
  cd $i || exit 1
  rewriteHistory $i
  cd ..
done

# Checkout mono-repo and apply changes from masters
checkoutProject vaadin-flow-components

# Create folder for creating the final vaadin-flow-components repo
finalDir=final-vaadin-flow-components
rm -rf $finalDir
mkdir $finalDir
cd $finalDir || exit 1

## Create the new repo
createNewRepo
## Merge all modules in the new repo
for i in $modules
do
  mergeModule $i
done

## Run this for having a new history with the changes done in monorepo
mergeFlowComponentsWithNewCommits() {
  for i in scripts pom.xml README.md build.sh LICENSE vaadin-flow-components-shared
  do
    cp -r ../vaadin-flow-components/$i . || exit 1
    git add $i
  done
  chown 755 scripts/* build.sh

  git commit -m 'feature: add maintenance scripts for monorepo' scripts build.sh
  git commit -m 'feature: add parent pom' pom.xml
  git commit -m 'feature: add shared project for ITs' vaadin-flow-components-shared
  git commit -m 'chore: Add README and LICENSE files' -a

  ./scripts/updateFromMaster.sh
  git commit -m 'feature: unify pom files in all modules' vaadin*parent/pom.xml vaadin*parent/vaadin-*/pom.xml
  git add vaadin*
  git commit -m 'chore: update sources from master' -a
}

## Run this for keeping history done in monorepo during Q3
mergeFlowComponentsWithOldCommits() {
  cd ../vaadin-flow-components || exit 1
  bash -x ./scripts/updateFromMaster.sh
  git add vaadin*
  git commit -m 'chore: update sources from original repos' -a
  cd ../$finalDir || exit 1 
  mergeModule vaadin-flow-components
}

git remote add origin git@github.com:vaadin/vaadin-flow-components.git
#mergeFlowComponentsWithNewCommits
mergeFlowComponentsWithOldCommits

## Reduce size of the repo
removeBigCommits
compressGit

## Branch for forcing pushi
git checkout -b full-history
git push -f





