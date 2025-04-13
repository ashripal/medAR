import numpy as np
import nibabel as nib
from skimage import measure, filters
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf
from collections import defaultdict
from scipy.ndimage import zoom
import plotly.graph_objects as go

COLOR_MAP = {
    'pink': (0.9, 0.7, 0.7),
    'red': (1.0, 0.0, 0.0),
    'yellow': (0.9, 0.9, 0.5),
    'lightblue': (0.7, 0.7, 0.9)
}
DOWNSAMPLE_FACTOR = 0.6

def get_tumors(tumor_path):
    
    seg_data = nib.load(seg_path).get_fdata()

    tumor_data = defaultdict(list)
    # Tumor label colors
    tumor_labels = {
        1: ("Edema", 'yellow', 0.3),
        2: ("Necrotic", 'red', 0.8),
        3: ("Enhancing", 'lightblue', 0.3)
    }

    # Add each tumor region
    for label, (name, color, opacity) in tumor_labels.items():
        mask = (seg_data == label).astype(np.uint8)
        if np.sum(mask) == 0:
            continue

        small_volume = zoom(mask.astype(float), DOWNSAMPLE_FACTOR)
        verts, faces, _, _ = measure.marching_cubes(small_volume, level=0.5)

        print(f'Num vertices: {name} | {len(verts)}')
        tumor_data[name] = (verts, faces, color, opacity)

    return tumor_data

def create_3d_html(mesh_data):
    data = []

    # Use brain first
    vertices, faces, color, opacity = mesh_data['brain']
    data.append(go.Mesh3d(
            x=vertices[:, 0],
            y=vertices[:, 1],
            z=vertices[:, 2],
            i=faces[:, 0],
            j=faces[:, 1],
            k=faces[:, 2],
            color= color,
            opacity= opacity,
            name= 'brain'
        ))

    for name in mesh_data.keys():
        if name == 'brain': continue
        vertices, faces, color, opacity = mesh_data[name]
        
        data.append(go.Mesh3d(
            x=vertices[:, 0],
            y=vertices[:, 1],
            z=vertices[:, 2],
            i=faces[:, 0],
            j=faces[:, 1],
            k=faces[:, 2],
            color= color,
            opacity= opacity,
            name= name
        ))
    
    fig = go.Figure(data = data)

    # Save plotly figure as HTML
    fig.write_html("brain_plot.html")

def create_usdc_with_materials(filename, mesh_data_dict):
    stage = Usd.Stage.CreateNew(filename)
    stage.SetDefaultPrim(stage.DefinePrim("/World", "Xform"))

    for name, (vertices, faces, color, opacity) in mesh_data_dict.items():
        color_tuple = COLOR_MAP[color]
        mesh_path = f"/World/{name}"
        mesh_prim = UsdGeom.Mesh.Define(stage, Sdf.Path(mesh_path))

        print("Vertices:", vertices[:10])  # Print first 10 vertices to check
        print("Faces:", faces[:10])  # Print first 10 faces to check

        points = [Gf.Vec3f(float(x), float(y), float(z)) for x, y, z in vertices]

        print("Points:", points[:10])  # Print first 10 points to check

        face_vertex_indices = faces.flatten().tolist()
        print("Face Vertex Indices:", face_vertex_indices[:10])  # Print first 10 to check
        face_vertex_counts = [3] * len(faces)

        mesh_prim.CreatePointsAttr(points)
        mesh_prim.CreateFaceVertexIndicesAttr(face_vertex_indices)
        mesh_prim.CreateFaceVertexCountsAttr(face_vertex_counts)

        # Normals (optional)
        mesh_prim.CreateNormalsAttr([Gf.Vec3f(0.0, 0.0, 1.0)] * len(vertices))
        mesh_prim.SetNormalsInterpolation("vertex")

        # Material
        mat_path = f"/Materials/{name}Mat"
        shader_path = f"/Materials/{name}Mat/Shader"

        material = UsdShade.Material.Define(stage, Sdf.Path(mat_path))
        shader = UsdShade.Shader.Define(stage, Sdf.Path(shader_path))
        shader.CreateIdAttr("UsdPreviewSurface")
        shader.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(float(color_tuple[0]), float(color_tuple[1]), float(color_tuple[2])))
        shader.CreateOutput("surface", Sdf.ValueTypeNames.Token)
        material.CreateSurfaceOutput().ConnectToSource(shader.GetOutput("surface"))
        UsdShade.MaterialBindingAPI(mesh_prim).Bind(material)

    print(stage.GetRootLayer().ExportToString())  # Debug the USD content before saving

    # Save the USD stage
    stage.GetRootLayer().Save()


if __name__ == '__main__':
    seg_path = "Task01_BrainTumour\labelsTr\BRATS_001.nii.gz" 
    tumor_data = get_tumors(seg_path)

    # Generate brain surface from MRI
    mri_data = nib.load('Task01_BrainTumour/imagesTr/BRATS_001.nii.gz')
    mri_data = mri_data.get_fdata()[:,:,:,3]

    brain_threshold = filters.threshold_otsu(mri_data)
    brain_mask = mri_data > brain_threshold
    small_volume = zoom(brain_mask.astype(float), DOWNSAMPLE_FACTOR)

    verts, faces, _, _ = measure.marching_cubes(small_volume.astype(np.uint8), level=0.5)
    print(f'Num vertices: Brain | {len(verts)}')
    tumor_data['brain'] = (verts, faces, 'pink', 0.2)

    create_3d_html(tumor_data)
    
    usdc_path = "brain_with_tumor.usdc"
    create_usdc_with_materials(usdc_path, tumor_data)
