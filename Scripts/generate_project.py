import hashlib, json
from pathlib import Path
root = Path(__file__).resolve().parents[1]
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
objects = {}
def obj(object_name, isa, **kwargs):
    key = ident(object_name); objects[key] = dict(isa=isa, **kwargs); return key
files = []
for name in ['SenseVoicePrototypeApp.swift','AppModel.swift','ContentView.swift','TextExportView.swift','StorageView.swift','ExportLocations.swift','GoogleDriveService.swift']:
    ref = obj(name, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=name, sourceTree='<group>')
    build = obj(name+'build','PBXBuildFile', fileRef=ref); files.append((ref, build))
info = obj('info','PBXFileReference',lastKnownFileType='text.plist.xml',path='Info.plist',sourceTree='<group>')
assets = obj('assets', 'PBXFileReference', lastKnownFileType='folder.assetcatalog', path='Assets.xcassets', sourceTree='<group>')
assetbuild = obj('assetsBuild', 'PBXBuildFile', fileRef=assets)
appgroup = obj('appgroup','PBXGroup',children=[r for r,b in files]+[info,assets],path='SenseVoiceApp',sourceTree='<group>')
product = obj('product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex='0',path='SenseVoicePrototype.app',sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products','PBXGroup',children=[product],name='Products',sourceTree='<group>')
main = obj('main','PBXGroup',children=[appgroup,products],sourceTree='<group>')
package = obj('package','XCLocalSwiftPackageReference',relativePath='.')
lib = obj('lib','XCSwiftPackageProductDependency',package=package,productName='SenseVoiceCore')
google = obj('googlePackage','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/google/GoogleSignIn-iOS.git',requirement=dict(kind='exactVersion',version='9.2.0'))
googleProducts = [obj(name+'Product','XCSwiftPackageProductDependency',package=google,productName=name) for name in ['GoogleSignIn','GoogleSignInSwift']]
googleBuilds = [obj(str(product)+'Build','PBXBuildFile',productRef=product) for product in googleProducts]
libbuild = obj('libbuild','PBXBuildFile',productRef=lib)
sources = obj('sources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=[b for r,b in files],runOnlyForDeploymentPostprocessing='0')
frameworks = obj('frameworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[libbuild]+googleBuilds,runOnlyForDeploymentPostprocessing='0')
resources = obj('resources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=[assetbuild],runOnlyForDeploymentPostprocessing='0')
configs=[]; projectconfigs=[]
for name in ['Debug','Release']:
    settings = dict(ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',PRODUCT_BUNDLE_IDENTIFIER='com.local.sensevoiceprototype',PRODUCT_NAME='$(TARGET_NAME)',INFOPLIST_FILE='SenseVoiceApp/Info.plist',GENERATE_INFOPLIST_FILE='NO',CODE_SIGN_STYLE='Automatic',IPHONEOS_DEPLOYMENT_TARGET='17.0',TARGETED_DEVICE_FAMILY='1,2',SWIFT_VERSION='5.0',SWIFT_STRICT_CONCURRENCY='targeted',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',SDKROOT='iphoneos',ENABLE_PREVIEWS='YES',ONLY_ACTIVE_ARCH='YES' if name=='Debug' else 'NO',SWIFT_OPTIMIZATION_LEVEL='-Onone' if name=='Debug' else '-O')
    configs.append(obj('target'+name,'XCBuildConfiguration',name=name,buildSettings=settings))
    projectconfigs.append(obj('project'+name,'XCBuildConfiguration',name=name,buildSettings=dict(CLANG_ENABLE_MODULES='YES',CLANG_ENABLE_OBJC_ARC='YES',SDKROOT='iphoneos',IPHONEOS_DEPLOYMENT_TARGET='17.0',SWIFT_VERSION='5.0',DEBUG_INFORMATION_FORMAT='dwarf' if name=='Debug' else 'dwarf-with-dsym')))
targetconfig = obj('targetconfig','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
projectconfig = obj('projectconfig','XCConfigurationList',buildConfigurations=projectconfigs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
target = obj('target','PBXNativeTarget',buildConfigurationList=targetconfig,buildPhases=[sources,frameworks,resources],buildRules=[],dependencies=[],name='SenseVoicePrototype',packageProductDependencies=[lib]+googleProducts,productName='SenseVoicePrototype',productReference=product,productType='com.apple.product-type.application')
project = obj('project','PBXProject',attributes=dict(BuildIndependentTargetsInParallel='YES',LastUpgradeCheck='2600'),buildConfigurationList=projectconfig,compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings='0',knownRegions=['zh-Hans','en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',packageReferences=[package,google],targets=[target])
def render(value, indent=0):
    if isinstance(value, dict):
        return '{\n' + '\n'.join('\t'*(indent+1)+json.dumps(k)+' = '+render(v,indent+1)+';' for k,v in value.items()) + '\n'+'\t'*indent+'}'
    if isinstance(value,list): return '(' + ', '.join(render(v,indent) for v in value) + (',' if value else '') + ')'
    return json.dumps(value,ensure_ascii=False)
(root/'SenseVoicePrototype.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n'+render(dict(archiveVersion='1',classes={},objectVersion='56',objects=objects,rootObject=project))+'\n')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SenseVoicePrototype.app" BlueprintName="SenseVoicePrototype" ReferencedContainer="container:SenseVoicePrototype.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SenseVoicePrototype.app" BlueprintName="SenseVoicePrototype" ReferencedContainer="container:SenseVoicePrototype.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SenseVoicePrototype.app" BlueprintName="SenseVoicePrototype" ReferencedContainer="container:SenseVoicePrototype.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root/'SenseVoicePrototype.xcodeproj/xcshareddata/xcschemes/SenseVoicePrototype.xcscheme').write_text(scheme)
